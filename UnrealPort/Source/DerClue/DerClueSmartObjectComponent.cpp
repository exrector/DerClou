#include "DerClueSmartObjectComponent.h"

#include "Components/PrimitiveComponent.h"
#include "Components/StaticMeshComponent.h"
#include "GameFramework/Actor.h"
#include "Engine/StaticMesh.h"

UDerClueSmartObjectComponent::UDerClueSmartObjectComponent()
{
    PrimaryComponentTick.bCanEverTick = true;
    PrimaryComponentTick.bStartWithTickEnabled = false;
}

void UDerClueSmartObjectComponent::BeginPlay()
{
    Super::BeginPlay();
    if (AActor* Owner = GetOwner())
    {
        ClosedRotation = Owner->GetActorRotation();
        ClosedLocation = Owner->GetActorLocation();
        FVector BoundsOrigin;
        FVector BoundsExtent;
        Owner->GetActorBounds(false, BoundsOrigin, BoundsExtent);
        DoorHalfLength = FMath::Max(BoundsExtent.X, BoundsExtent.Y);
        DoorClosedAxis = Owner->GetActorForwardVector();
        if (UStaticMeshComponent* Mesh = Owner->FindComponentByClass<UStaticMeshComponent>())
        {
            if (const UStaticMesh* StaticMesh = Mesh->GetStaticMesh())
            {
                const FVector LocalExtent = StaticMesh->GetBounds().BoxExtent * Mesh->GetComponentScale().GetAbs();
                const bool bLongAlongY = LocalExtent.Y > LocalExtent.X;
                DoorHalfLength = bLongAlongY ? LocalExtent.Y : LocalExtent.X;
                DoorClosedAxis = bLongAlongY ? Mesh->GetRightVector() : Mesh->GetForwardVector();
            }
        }
        DoorClosedAxis.Z = 0.0f;
        DoorClosedAxis.Normalize();
        HingeLocation = ClosedLocation - DoorClosedAxis * DoorHalfLength;
        DoorOpenAlpha = bOpen ? 1.0f : 0.0f;
        TArray<UPrimitiveComponent*> Primitives;
        Owner->GetComponents(Primitives);
        for (UPrimitiveComponent* Primitive : Primitives)
        {
            if (!Primitive)
            {
                continue;
            }
            Primitive->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
            Primitive->SetCollisionResponseToChannel(ECC_Pawn, ECR_Block);
            Primitive->SetCollisionResponseToChannel(ECC_Visibility, ECR_Block);
            Primitive->SetCanEverAffectNavigation(true);
        }
        ApplyDoorState();
        SetComponentTickEnabled(false);
    }
}

void UDerClueSmartObjectComponent::TickComponent(float DeltaTime, ELevelTick TickType,
    FActorComponentTickFunction* ThisTickFunction)
{
    Super::TickComponent(DeltaTime, TickType, ThisTickFunction);
    UpdateDoor(DeltaTime);
}

void UDerClueSmartObjectComponent::UpdateDoor(float DeltaTime)
{
    if (Kind != EDerClueSmartObjectKind::Door)
    {
        SetComponentTickEnabled(false);
        return;
    }
    const float Target = bOpen ? 1.0f : 0.0f;
    DoorOpenAlpha = FMath::FInterpConstantTo(DoorOpenAlpha, Target, DeltaTime,
        1.0f / FMath::Max(0.05f, DoorTransitionSeconds));
    ApplyDoorState();
    if (FMath::IsNearlyEqual(DoorOpenAlpha, Target, KINDA_SMALL_NUMBER))
    {
        DoorOpenAlpha = Target;
        ApplyDoorState();
        SetComponentTickEnabled(false);
    }
}

bool UDerClueSmartObjectComponent::Interact(AActor* InstigatorActor)
{
    if (!InstigatorActor || !GetOwner() ||
        FVector::Dist2D(InstigatorActor->GetActorLocation(), GetOwner()->GetActorLocation()) > InteractionRadius)
    {
        return false;
    }

    switch (Kind)
    {
        case EDerClueSmartObjectKind::Door:
            if (bLocked)
            {
                return false;
            }
            SetOpen(!bOpen);
            return true;
        case EDerClueSmartObjectKind::SecurityPanel:
            bPowered = false;
            return true;
        case EDerClueSmartObjectKind::Safe:
            if (bLocked)
            {
                bLocked = false;
            }
            else
            {
                bOpen = true;
            }
            return true;
        case EDerClueSmartObjectKind::Furniture:
            return true;
        case EDerClueSmartObjectKind::Loot:
            if (bCollected)
            {
                return false;
            }
            bCollected = true;
            GetOwner()->SetActorHiddenInGame(true);
            GetOwner()->SetActorEnableCollision(false);
            return true;
        case EDerClueSmartObjectKind::Extraction:
            return true;
    }
    return false;
}

void UDerClueSmartObjectComponent::SetOpen(bool bNewOpen)
{
    if (Kind != EDerClueSmartObjectKind::Door || bLocked || bOpen == bNewOpen)
    {
        return;
    }
    bOpen = bNewOpen;
}

void UDerClueSmartObjectComponent::ApplyDoorState()
{
    if (Kind == EDerClueSmartObjectKind::Door && GetOwner())
    {
        const float AppliedYaw = OpenYaw * DoorOpenAlpha;
        FRotator Rotation = ClosedRotation;
        Rotation.Yaw += AppliedYaw;
        const FVector RotatedAxis = FQuat(FVector::UpVector, FMath::DegreesToRadians(AppliedYaw)).RotateVector(DoorClosedAxis);
        const FVector NewLocation = HingeLocation + RotatedAxis * DoorHalfLength;
        GetOwner()->SetActorLocationAndRotation(NewLocation, Rotation);
    }
}
