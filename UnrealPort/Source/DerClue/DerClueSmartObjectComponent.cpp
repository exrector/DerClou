#include "DerClueSmartObjectComponent.h"

#include "NavAreas/NavArea_Default.h"
#include "NavAreas/NavArea_Null.h"
#include "NavModifierComponent.h"

#include "Components/PrimitiveComponent.h"
#include "Components/StaticMeshComponent.h"
#include "GameFramework/Actor.h"
#include "Engine/StaticMesh.h"
#include "Perception/AISense_Hearing.h"

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
        // BoundsOrigin is the true centre of the slab; ClosedLocation is only
        // the pivot, which on the prototype cubes sits on a corner. Swinging
        // around a hinge derived from the pivot threw the door ~80cm off the
        // doorway and left it fouling the opening it was supposed to clear.
        ClosedCenterOffset = BoundsOrigin - ClosedLocation;
        HingeLocation = BoundsOrigin - DoorClosedAxis * DoorHalfLength;
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
            // Doors are excluded here rather than corrected a frame later, so a
            // dynamic navmesh never sees a transient hole across the doorway.
            Primitive->SetCanEverAffectNavigation(Kind != EDerClueSmartObjectKind::Door);
        }
        if (Kind == EDerClueSmartObjectKind::Door && !NavModifier)
        {
            NavModifier = NewObject<UNavModifierComponent>(Owner);
            NavModifier->RegisterComponent();
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
    SetComponentTickEnabled(true);
}

void UDerClueSmartObjectComponent::EmitNoise(AActor* InstigatorActor)
{
    if (Kind != EDerClueSmartObjectKind::Door || !GetOwner())
    {
        return;
    }
    UAISense_Hearing::ReportNoiseEvent(this, GetOwner()->GetActorLocation(),
        NoiseLoudness, InstigatorActor ? InstigatorActor : GetOwner(),
        NoiseMaxRange, TEXT("DoorNoise"));
}

void UDerClueSmartObjectComponent::RestoreState(bool bNewLocked, bool bNewOpen,
    bool bNewPowered, bool bNewCollected)
{
    bLocked = bNewLocked;
    bOpen = bNewOpen;
    bPowered = bNewPowered;
    bCollected = bNewCollected;
    DoorOpenAlpha = bOpen ? 1.0f : 0.0f;
    if (AActor* Owner = GetOwner())
    {
        Owner->SetActorHiddenInGame(bCollected);
        Owner->SetActorEnableCollision(!bCollected);
    }
    ApplyDoorState();
    SetComponentTickEnabled(false);
}

void UDerClueSmartObjectComponent::ApplyDoorState()
{
    if (Kind == EDerClueSmartObjectKind::Door && GetOwner())
    {
        const float AppliedYaw = OpenYaw * DoorOpenAlpha;
        FRotator Rotation = ClosedRotation;
        Rotation.Yaw += AppliedYaw;
        const FQuat YawQuat(FVector::UpVector, FMath::DegreesToRadians(AppliedYaw));
        const FVector RotatedAxis = YawQuat.RotateVector(DoorClosedAxis);
        const FVector NewCenter = HingeLocation + RotatedAxis * DoorHalfLength;
        GetOwner()->SetActorLocationAndRotation(NewCenter - YawQuat.RotateVector(ClosedCenterOffset), Rotation);
        TArray<UPrimitiveComponent*> Primitives;
        GetOwner()->GetComponents(Primitives);
        const bool bPassable = DoorOpenAlpha >= 0.75f;
        for (UPrimitiveComponent* Primitive : Primitives)
        {
            Primitive->SetCollisionResponseToChannel(ECC_Pawn, bPassable ? ECR_Ignore : ECR_Block);
            Primitive->SetCollisionResponseToChannel(ECC_Visibility, bPassable ? ECR_Ignore : ECR_Block);
            // The swinging slab must never be navmesh geometry. Epic's guidance
            // is that movable geometry does not carve navmesh, and here it also
            // made the doorway vanish from the graph while shut.
            Primitive->SetCanEverAffectNavigation(false);
        }
        ApplyDoorNavigation();
    }
}

void UDerClueSmartObjectComponent::ApplyDoorNavigation()
{
    if (!NavModifier)
    {
        return;
    }
    // Only a locked door is genuinely impassable, and only that case may remove
    // the doorway from the navmesh. A shut-but-unlocked door stays navigable so
    // a route exists; the pawn is still physically blocked until it arrives and
    // the proximity logic swings the slab open.
    NavModifier->SetAreaClass(bLocked
        ? UNavArea_Null::StaticClass()
        : UNavArea_Default::StaticClass());
}
