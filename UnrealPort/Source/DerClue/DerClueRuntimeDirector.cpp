#include "DerClueRuntimeDirector.h"

#include "AIController.h"
#include "DerClueSmartObjectComponent.h"
#include "Engine/OverlapResult.h"
#include "Engine/SpotLight.h"
#include "EngineUtils.h"
#include "GameFramework/Character.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Kismet/GameplayStatics.h"
#include "NavigationSystem.h"
#include "NavModifierComponent.h"
#include "NavAreas/NavArea_Obstacle.h"
#include "Components/CapsuleComponent.h"
#include "Components/SpotLightComponent.h"
#include "Components/PointLightComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/StaticMeshActor.h"
#include "DrawDebugHelpers.h"
#include "InputCoreTypes.h"
#include "Navigation/PathFollowingComponent.h"

ADerClueRuntimeDirector::ADerClueRuntimeDirector()
{
    PrimaryActorTick.bCanEverTick = true;
    PrimaryActorTick.TickInterval = 1.0f / 30.0f;
}

void ADerClueRuntimeDirector::BeginPlay()
{
    Super::BeginPlay();
    DiscoverLevelActors();
    ConfigureCharacter(Guard);
    ConfigureCharacter(Thief);
    ConfigureVisionLights();
    ConfigureWorldAndSmartObjects();
    if (Thief)
    {
        ThiefNavObstacle = NewObject<UNavModifierComponent>(Thief, TEXT("DerClueStationaryObstacle"));
        ThiefNavObstacle->SetAreaClass(UNavArea_Obstacle::StaticClass());
        ThiefNavObstacle->SetCanEverAffectNavigation(false);
        ThiefNavObstacle->RegisterComponent();
    }
    ReturnToNearestPatrolNode();
}

void ADerClueRuntimeDirector::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);
    UpdateCameras(DeltaSeconds);
    UpdateVision();
    UpdateAlarmPresentation();
    UpdateSmartObjects();
    UpdateDynamicActorAvoidance();
    UpdatePatrol();
    UpdateMissionState();
    UpdateTechnicalOverlay();
}

void ADerClueRuntimeDirector::UpdateMissionState()
{
    if (MissionState != EDerClueMissionState::InProgress || !Guard || !Thief)
    {
        return;
    }
    if (SecurityState == EDerClueSecurityState::Alarm &&
        FVector::Dist2D(Guard->GetActorLocation(), Thief->GetActorLocation()) <= CaptureDistance &&
        CanSeeTarget(Guard, Thief, CaptureDistance + 25.0f, 160.0f))
    {
        MissionState = EDerClueMissionState::Failed;
        SecurityState = EDerClueSecurityState::Lockdown;
        if (GuardController)
        {
            GuardController->StopMovement();
        }
    }
}

void ADerClueRuntimeDirector::DrawVisionFootprint(const AActor* Source, float Range,
    float FullAngleDegrees, const FColor& Color) const
{
    if (!Source || !GetWorld())
    {
        return;
    }
    constexpr int32 RayCount = 24;
    const FVector SourceWorld = Source->GetActorLocation();
    const FVector DebugOrigin(SourceWorld.X, SourceWorld.Y, 18.0f);
    const float BaseYaw = Source->GetActorRotation().Yaw;
    FVector PreviousEnd = DebugOrigin;
    for (int32 Index = 0; Index <= RayCount; ++Index)
    {
        const float Alpha = static_cast<float>(Index) / RayCount;
        const float Yaw = BaseYaw + FMath::Lerp(-FullAngleDegrees * 0.5f, FullAngleDegrees * 0.5f, Alpha);
        const FVector Direction = FRotator(0.0f, Yaw, 0.0f).Vector();
        FVector TraceEnd = SourceWorld + Direction * Range;
        FHitResult Hit;
        FCollisionQueryParams Params(SCENE_QUERY_STAT(DerClueDebugVision), true, Source);
        Params.AddIgnoredActor(Source);
        if (GetWorld()->LineTraceSingleByChannel(Hit, SourceWorld, TraceEnd, ECC_Visibility, Params))
        {
            TraceEnd = Hit.ImpactPoint;
        }
        const FVector DebugEnd(TraceEnd.X, TraceEnd.Y, 18.0f);
        if (Index == 0 || Index == RayCount || Index % 4 == 0)
        {
            DrawDebugLine(GetWorld(), DebugOrigin, DebugEnd, Color, false, 0.0f, 0, 1.5f);
        }
        if (Index > 0)
        {
            DrawDebugLine(GetWorld(), PreviousEnd, DebugEnd, Color, false, 0.0f, 0, 2.0f);
        }
        PreviousEnd = DebugEnd;
    }
}

void ADerClueRuntimeDirector::UpdateTechnicalOverlay()
{
    if (APlayerController* PlayerController = GetWorld()->GetFirstPlayerController())
    {
        if (PlayerController->WasInputKeyJustPressed(EKeys::T))
        {
            bTechnicalOverlay = !bTechnicalOverlay;
        }
    }

    if (bShowPatrolRoute && PatrolNodes.Num() > 1)
    {
        for (int32 Index = 0; Index < PatrolNodes.Num(); ++Index)
        {
            const FVector A = PatrolNodes[Index]->GetActorLocation() + FVector(0, 0, 12);
            const FVector B = PatrolNodes[(Index + 1) % PatrolNodes.Num()]->GetActorLocation() + FVector(0, 0, 12);
            DrawDebugLine(GetWorld(), A, B, FColor::Cyan, false, 0.0f, 0, 3.0f);
            DrawDebugSphere(GetWorld(), A, 18.0f, 12, FColor::Cyan, false, 0.0f, 0, 2.0f);
        }
    }

    if (!bTechnicalOverlay)
    {
        return;
    }
    DrawVisionFootprint(Guard, GuardVisionRange, GuardVisionAngle, FColor::Yellow);
    if (bCamerasPowered)
    {
        for (AActor* Camera : SecurityCameras)
        {
            DrawVisionFootprint(Camera, CameraVisionRange, CameraVisionAngle, FColor::Red);
        }
    }
    if (GuardController && GuardController->GetPathFollowingComponent())
    {
        const FNavPathSharedPtr Path = GuardController->GetPathFollowingComponent()->GetPath();
        if (Path.IsValid())
        {
            const TArray<FNavPathPoint>& Points = Path->GetPathPoints();
            for (int32 Index = 1; Index < Points.Num(); ++Index)
            {
                DrawDebugLine(GetWorld(), Points[Index - 1].Location + FVector(0, 0, 20),
                    Points[Index].Location + FVector(0, 0, 20), FColor::Green, false, 0.0f, 0, 4.0f);
            }
        }
    }
    if (GEngine)
    {
        const UEnum* SecurityEnum = StaticEnum<EDerClueSecurityState>();
        const UEnum* MissionEnum = StaticEnum<EDerClueMissionState>();
        GEngine->AddOnScreenDebugMessage(7711, 0.0f, FColor::White,
            FString::Printf(TEXT("TECHNICAL [T]  Security: %s  Mission: %s  Loot: %s"),
                SecurityEnum ? *SecurityEnum->GetNameStringByValue(static_cast<int64>(SecurityState)) : TEXT("Unknown"),
                MissionEnum ? *MissionEnum->GetNameStringByValue(static_cast<int64>(MissionState)) : TEXT("Unknown"),
                bHasLoot ? TEXT("YES") : TEXT("NO")));
    }
}

void ADerClueRuntimeDirector::DiscoverLevelActors()
{
    TArray<AActor*> Found;
    UGameplayStatics::GetAllActorsWithTag(this, GuardTag, Found);
    Guard = Found.Num() > 0 ? Cast<ACharacter>(Found[0]) : nullptr;
    Found.Reset();
    UGameplayStatics::GetAllActorsWithTag(this, ThiefTag, Found);
    Thief = Found.Num() > 0 ? Cast<ACharacter>(Found[0]) : nullptr;
    Found.Reset();
    UGameplayStatics::GetAllActorsWithTag(this, PatrolNodeTag, Found);
    Found.Sort([](const AActor& A, const AActor& B)
    {
        const FString AOrder = A.Tags.Num() > 1 ? A.Tags[1].ToString() : A.GetName();
        const FString BOrder = B.Tags.Num() > 1 ? B.Tags[1].ToString() : B.GetName();
        return AOrder < BOrder;
    });
    for (AActor* Actor : Found)
    {
        Actor->SetActorHiddenInGame(true);
        TArray<UPrimitiveComponent*> MarkerPrimitives;
        Actor->GetComponents(MarkerPrimitives);
        for (UPrimitiveComponent* Primitive : MarkerPrimitives)
        {
            Primitive->SetCollisionEnabled(ECollisionEnabled::NoCollision);
            Primitive->SetCanEverAffectNavigation(false);
        }
        PatrolNodes.Add(Actor);
    }
    Found.Reset();
    UGameplayStatics::GetAllActorsWithTag(this, SecurityCameraTag, Found);
    for (AActor* Actor : Found)
    {
        SecurityCameras.Add(Actor);
        CameraBaseRotations.Add(Actor, Actor->GetActorRotation());
    }
    Found.Reset();
    UGameplayStatics::GetAllActorsWithTag(this, CameraVisualTag, Found);
    for (AActor* Actor : Found)
    {
        if (UStaticMeshComponent* VisualMesh = Actor->FindComponentByClass<UStaticMeshComponent>())
        {
            VisualMesh->SetMobility(EComponentMobility::Movable);
        }
        CameraVisuals.Add(Actor);
    }
    Found.Reset();
    UGameplayStatics::GetAllActorsWithTag(this, AlarmLightTag, Found);
    for (AActor* Actor : Found)
    {
        if (UPointLightComponent* Light = Actor ? Actor->FindComponentByClass<UPointLightComponent>() : nullptr)
        {
            Light->SetMobility(EComponentMobility::Movable);
            Light->SetVisibility(true);
            AlarmLights.Add(Light);
        }
    }

    if (Guard)
    {
        GuardController = Cast<AAIController>(Guard->GetController());
        if (!GuardController)
        {
            GuardController = GetWorld()->SpawnActor<AAIController>();
            if (GuardController)
            {
                GuardController->Possess(Guard);
            }
        }
    }
}

void ADerClueRuntimeDirector::ConfigureWorldAndSmartObjects()
{
    for (TActorIterator<AStaticMeshActor> It(GetWorld()); It; ++It)
    {
        AStaticMeshActor* Actor = *It;
        if (!Actor || Actor->ActorHasTag(PatrolNodeTag))
        {
            continue;
        }
        if (UPrimitiveComponent* Primitive = Actor->GetStaticMeshComponent())
        {
            Primitive->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
            Primitive->SetCollisionResponseToChannel(ECC_Pawn, ECR_Block);
            Primitive->SetCollisionResponseToChannel(ECC_Visibility, ECR_Block);
            Primitive->SetCanEverAffectNavigation(true);
        }

        EDerClueSmartObjectKind Kind;
        bool bIsSmart = true;
        if (Actor->ActorHasTag(TEXT("DerClue.Door")))
        {
            Kind = EDerClueSmartObjectKind::Door;
        }
        else if (Actor->ActorHasTag(TEXT("DerClue.SecurityPanel")))
        {
            Kind = EDerClueSmartObjectKind::SecurityPanel;
        }
        else if (Actor->ActorHasTag(TEXT("DerClue.Safe")))
        {
            Kind = EDerClueSmartObjectKind::Safe;
        }
        else if (Actor->ActorHasTag(TEXT("Loot")))
        {
            Kind = EDerClueSmartObjectKind::Loot;
        }
        else if (Actor->ActorHasTag(TEXT("Extraction")))
        {
            Kind = EDerClueSmartObjectKind::Extraction;
        }
        else
        {
            bIsSmart = false;
            Kind = EDerClueSmartObjectKind::Furniture;
        }

        if (bIsSmart)
        {
            if (Kind == EDerClueSmartObjectKind::Door || Kind == EDerClueSmartObjectKind::Safe)
            {
                if (UPrimitiveComponent* MovablePrimitive = Actor->GetStaticMeshComponent())
                {
                    MovablePrimitive->SetMobility(EComponentMobility::Movable);
                }
            }
            if (Kind == EDerClueSmartObjectKind::Loot || Kind == EDerClueSmartObjectKind::Extraction)
            {
                if (UPrimitiveComponent* TriggerPrimitive = Actor->GetStaticMeshComponent())
                {
                    TriggerPrimitive->SetCollisionResponseToChannel(ECC_Pawn, ECR_Overlap);
                    TriggerPrimitive->SetCanEverAffectNavigation(false);
                }
            }
            UDerClueSmartObjectComponent* Component = NewObject<UDerClueSmartObjectComponent>(Actor);
            Component->Kind = Kind;
            Component->StableId = Actor->GetFName();
            Component->bLocked = Kind == EDerClueSmartObjectKind::Safe;
            Component->RegisterComponent();
            SmartObjects.Add(Component);
        }
    }
}

void ADerClueRuntimeDirector::ConfigureCharacter(ACharacter* Character) const
{
    if (!Character)
    {
        return;
    }
    if (UCapsuleComponent* Capsule = Character->GetCapsuleComponent())
    {
        Capsule->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
        Capsule->SetCollisionResponseToChannel(ECC_Pawn, ECR_Block);
        Capsule->SetCollisionResponseToChannel(ECC_WorldStatic, ECR_Block);
        Capsule->SetCollisionResponseToChannel(ECC_WorldDynamic, ECR_Block);
    }
    if (UCharacterMovementComponent* Movement = Character->GetCharacterMovement())
    {
        Movement->MaxWalkSpeed = 260.0f;
        Movement->MaxAcceleration = 700.0f;
        Movement->BrakingDecelerationWalking = 900.0f;
        if (FNavMovementProperties* NavMovement = Movement->GetNavMovementProperties())
        {
            NavMovement->bUseAccelerationForPaths = true;
        }
        Movement->bOrientRotationToMovement = true;
        Movement->RotationRate = FRotator(0.0f, 300.0f, 0.0f);
        Movement->bUseRVOAvoidance = true;
        Movement->AvoidanceConsiderationRadius = 220.0f;
    }
}

void ADerClueRuntimeDirector::UpdateDynamicActorAvoidance()
{
    if (!Guard || !Thief || !ThiefNavObstacle)
    {
        return;
    }
    const float Now = GetWorld()->GetTimeSeconds();
    const float Speed = Thief->GetVelocity().Size2D();
    const float GuardDistance = FVector::Dist2D(Guard->GetActorLocation(), Thief->GetActorLocation());
    const bool bInsideInfluence = GuardDistance <= StationaryObstacleInfluenceRadius;

    if (Speed <= 5.0f && bInsideInfluence)
    {
        if (ThiefStationarySince < 0.0f)
        {
            ThiefStationarySince = Now;
        }
        if (!bThiefNavObstacleEnabled && Now - ThiefStationarySince >= StationaryObstacleActivationDelay)
        {
            bThiefNavObstacleEnabled = true;
            ThiefNavObstacle->SetCanEverAffectNavigation(true);
            NextMoveRequestTime = 0.0f;
        }
    }
    else
    {
        ThiefStationarySince = -1.0f;
        if (bThiefNavObstacleEnabled && (Speed >= 20.0f || GuardDistance > StationaryObstacleInfluenceRadius + 180.0f))
        {
            bThiefNavObstacleEnabled = false;
            ThiefNavObstacle->SetCanEverAffectNavigation(false);
            NextMoveRequestTime = 0.0f;
        }
    }
}

void ADerClueRuntimeDirector::ConfigureVisionLights()
{
    if (Guard)
    {
        TArray<USpotLightComponent*> Lights;
        Guard->GetComponents(Lights);
        for (USpotLightComponent* Light : Lights)
        {
            Light->SetVisibility(true);
            Light->SetAttenuationRadius(GuardVisionRange);
            Light->SetInnerConeAngle(GuardVisionAngle * 0.20f);
            Light->SetOuterConeAngle(GuardVisionAngle * 0.50f);
            Light->SetCastShadows(true);
        }
    }
    for (AActor* Camera : SecurityCameras)
    {
        TArray<USpotLightComponent*> Lights;
        Camera->GetComponents(Lights);
        for (USpotLightComponent* Light : Lights)
        {
            Light->SetVisibility(true);
            Light->SetAttenuationRadius(CameraVisionRange);
            Light->SetInnerConeAngle(CameraVisionAngle * 0.28f);
            Light->SetOuterConeAngle(CameraVisionAngle * 0.50f);
            Light->SetCastShadows(true);
        }
    }
}

bool ADerClueRuntimeDirector::RequestMove(const FVector& Destination)
{
    if (!GuardController || !Guard || GetWorld()->GetTimeSeconds() < NextMoveRequestTime)
    {
        return false;
    }
    NextMoveRequestTime = GetWorld()->GetTimeSeconds() + RepathCooldown;
    const EPathFollowingRequestResult::Type Result = GuardController->MoveToLocation(
        Destination, PatrolAcceptanceRadius, true, true, true, false, nullptr, true);
    return Result != EPathFollowingRequestResult::Failed;
}

void ADerClueRuntimeDirector::UpdatePatrol()
{
    if (!Guard || !GuardController || PatrolNodes.IsEmpty())
    {
        return;
    }

    if (!bInvestigating && IsPatrolNodeOccupied(PatrolNodes[CurrentPatrolIndex]))
    {
        const int32 StartingIndex = CurrentPatrolIndex;
        do
        {
            CurrentPatrolIndex = (CurrentPatrolIndex + 1) % PatrolNodes.Num();
        }
        while (CurrentPatrolIndex != StartingIndex && IsPatrolNodeOccupied(PatrolNodes[CurrentPatrolIndex]));

        if (GuardController)
        {
            GuardController->StopMovement();
        }
        NextMoveRequestTime = 0.0f;
        RequestMove(PatrolNodes[CurrentPatrolIndex]->GetActorLocation());
    }

    const FVector Goal = bInvestigating ? InvestigationLocation : PatrolNodes[CurrentPatrolIndex]->GetActorLocation();
    if (FVector::Dist2D(Guard->GetActorLocation(), Goal) <= PatrolAcceptanceRadius)
    {
        if (bInvestigating)
        {
            if (SecurityState == EDerClueSecurityState::Normal ||
                GetWorld()->GetTimeSeconds() - LastDetectionTime >= AlertMemorySeconds)
            {
                SecurityState = EDerClueSecurityState::Normal;
                ReturnToNearestPatrolNode();
            }
        }
        else
        {
            do
            {
                CurrentPatrolIndex = (CurrentPatrolIndex + 1) % PatrolNodes.Num();
            }
            while (PatrolNodes.Num() > 1 && IsPatrolNodeOccupied(PatrolNodes[CurrentPatrolIndex]));
            RequestMove(PatrolNodes[CurrentPatrolIndex]->GetActorLocation());
        }
        return;
    }

    if (GuardController->GetMoveStatus() != EPathFollowingStatus::Moving)
    {
        if (!RequestMove(Goal) && !bInvestigating)
        {
            CurrentPatrolIndex = (CurrentPatrolIndex + 1) % PatrolNodes.Num();
            NextMoveRequestTime = 0.0f;
            RequestMove(PatrolNodes[CurrentPatrolIndex]->GetActorLocation());
        }
    }
}

void ADerClueRuntimeDirector::UpdateSmartObjects()
{
    for (UDerClueSmartObjectComponent* SmartObject : SmartObjects)
    {
        if (!SmartObject || !SmartObject->GetOwner())
        {
            continue;
        }
        SmartObject->UpdateDoor(GetWorld()->GetDeltaSeconds());
        const FVector ObjectLocation = SmartObject->GetOwner()->GetActorLocation();
        const float GuardDistance = Guard ? FVector::Dist2D(Guard->GetActorLocation(), ObjectLocation) : TNumericLimits<float>::Max();
        const float ThiefDistance = Thief ? FVector::Dist2D(Thief->GetActorLocation(), ObjectLocation) : TNumericLimits<float>::Max();
        const float Nearest = FMath::Min(GuardDistance, ThiefDistance);

        if (SmartObject->Kind == EDerClueSmartObjectKind::Door && Nearest <= SmartObject->InteractionRadius)
        {
            SmartObject->SetOpen(true);
        }
        else if (SmartObject->Kind == EDerClueSmartObjectKind::Door && Nearest >= SmartObject->InteractionRadius + 80.0f)
        {
            SmartObject->SetOpen(false);
        }
        else if (SmartObject->Kind == EDerClueSmartObjectKind::SecurityPanel &&
                 SmartObject->bPowered && Thief && ThiefDistance <= SmartObject->InteractionRadius)
        {
            if (SmartObject->Interact(Thief))
            {
                bCamerasPowered = false;
                for (AActor* Camera : SecurityCameras)
                {
                    TArray<USpotLightComponent*> Lights;
                    Camera->GetComponents(Lights);
                    for (USpotLightComponent* Light : Lights)
                    {
                        Light->SetVisibility(false);
                    }
                }
                SecurityState = EDerClueSecurityState::Normal;
            }
        }
        else if (SmartObject->Kind == EDerClueSmartObjectKind::Safe &&
                 Thief && ThiefDistance <= SmartObject->InteractionRadius &&
                 (SmartObject->bLocked || !SmartObject->bOpen))
        {
            SmartObject->Interact(Thief);
        }
        else if (SmartObject->Kind == EDerClueSmartObjectKind::Loot &&
                 Thief && ThiefDistance <= SmartObject->InteractionRadius && !SmartObject->bCollected)
        {
            bool bAnySafeOpen = false;
            for (UDerClueSmartObjectComponent* Candidate : SmartObjects)
            {
                bAnySafeOpen |= Candidate && Candidate->Kind == EDerClueSmartObjectKind::Safe && Candidate->bOpen;
            }
            if (bAnySafeOpen && SmartObject->Interact(Thief))
            {
                bHasLoot = true;
            }
        }
        else if (SmartObject->Kind == EDerClueSmartObjectKind::Extraction &&
                 Thief && ThiefDistance <= SmartObject->InteractionRadius && bHasLoot)
        {
            MissionState = EDerClueMissionState::Success;
        }
    }
}

bool ADerClueRuntimeDirector::IsPatrolNodeOccupied(const AActor* Node) const
{
    if (!Node || !GetWorld())
    {
        return true;
    }
    TArray<FOverlapResult> Results;
    FCollisionQueryParams Params(SCENE_QUERY_STAT(DerCluePatrolNode), false, Guard);
    const bool bHit = GetWorld()->OverlapMultiByObjectType(
        Results,
        Node->GetActorLocation(),
        FQuat::Identity,
        FCollisionObjectQueryParams(FCollisionObjectQueryParams::AllDynamicObjects),
        FCollisionShape::MakeSphere(OccupiedNodeRadius),
        Params);
    if (!bHit)
    {
        return false;
    }
    for (const FOverlapResult& Hit : Results)
    {
        AActor* HitActor = Hit.GetActor();
        if (HitActor && HitActor != Node && HitActor != Guard && Cast<APawn>(HitActor))
        {
            return true;
        }
    }
    return false;
}

int32 ADerClueRuntimeDirector::FindNearestReachablePatrolNode() const
{
    if (!Guard || PatrolNodes.IsEmpty())
    {
        return INDEX_NONE;
    }
    UNavigationSystemV1* Nav = UNavigationSystemV1::GetCurrent(GetWorld());
    float BestDistance = TNumericLimits<float>::Max();
    int32 BestIndex = INDEX_NONE;
    for (int32 Index = 0; Index < PatrolNodes.Num(); ++Index)
    {
        AActor* Node = PatrolNodes[Index];
        if (!Node || IsPatrolNodeOccupied(Node))
        {
            continue;
        }
        FNavLocation Projected;
        if (Nav && Nav->ProjectPointToNavigation(Node->GetActorLocation(), Projected))
        {
            const float Distance = FVector::DistSquared2D(Guard->GetActorLocation(), Projected.Location);
            if (Distance < BestDistance)
            {
                BestDistance = Distance;
                BestIndex = Index;
            }
        }
    }
    return BestIndex;
}

void ADerClueRuntimeDirector::InvestigateLocation(FVector WorldLocation)
{
    bInvestigating = true;
    InvestigationLocation = WorldLocation;
    if (GuardController)
    {
        GuardController->StopMovement();
    }
    NextMoveRequestTime = 0.0f;
    RequestMove(WorldLocation);
}

void ADerClueRuntimeDirector::ReturnToNearestPatrolNode()
{
    bInvestigating = false;
    const int32 Nearest = FindNearestReachablePatrolNode();
    if (Nearest != INDEX_NONE)
    {
        CurrentPatrolIndex = Nearest;
        if (GuardController)
        {
            GuardController->StopMovement();
        }
        NextMoveRequestTime = 0.0f;
        RequestMove(PatrolNodes[CurrentPatrolIndex]->GetActorLocation());
    }
}

bool ADerClueRuntimeDirector::CanSeeTarget(const AActor* Source, const AActor* Target, float Range, float FullAngleDegrees) const
{
    if (!Source || !Target || !GetWorld())
    {
        return false;
    }
    const FVector SourceLocation = Source->GetActorLocation();
    const FVector ToTarget = Target->GetActorLocation() - SourceLocation;
    if (ToTarget.SizeSquared2D() > FMath::Square(Range))
    {
        return false;
    }
    const FVector Direction2D = FVector(ToTarget.X, ToTarget.Y, 0.0f).GetSafeNormal();
    const FVector Forward2D = FVector(Source->GetActorForwardVector().X, Source->GetActorForwardVector().Y, 0.0f).GetSafeNormal();
    if (FVector::DotProduct(Direction2D, Forward2D) < FMath::Cos(FMath::DegreesToRadians(FullAngleDegrees * 0.5f)))
    {
        return false;
    }
    FHitResult Hit;
    FCollisionQueryParams Params(SCENE_QUERY_STAT(DerClueVision), true, Source);
    Params.AddIgnoredActor(Source);
    return GetWorld()->LineTraceSingleByChannel(Hit, SourceLocation, Target->GetActorLocation(), ECC_Visibility, Params)
        ? Hit.GetActor() == Target
        : true;
}

void ADerClueRuntimeDirector::UpdateVision()
{
    if (!Thief)
    {
        return;
    }
    bool bDetected = Guard && CanSeeTarget(Guard, Thief, GuardVisionRange, GuardVisionAngle);
    if (bCamerasPowered)
    {
        for (AActor* Camera : SecurityCameras)
        {
            bDetected |= CanSeeTarget(Camera, Thief, CameraVisionRange, CameraVisionAngle);
        }
    }
    if (bDetected)
    {
        const float Now = GetWorld()->GetTimeSeconds();
        SecurityState = EDerClueSecurityState::Alarm;
        LastDetectionTime = Now;
        if (!bInvestigating)
        {
            InvestigateLocation(Thief->GetActorLocation());
            NextInvestigationUpdateTime = Now + 0.6f;
        }
        else if (Now >= NextInvestigationUpdateTime &&
                 FVector::DistSquared2D(InvestigationLocation, Thief->GetActorLocation()) > FMath::Square(150.0f))
        {
            InvestigationLocation = Thief->GetActorLocation();
            NextMoveRequestTime = 0.0f;
            RequestMove(InvestigationLocation);
            NextInvestigationUpdateTime = Now + 0.6f;
        }
    }
    else if (SecurityState == EDerClueSecurityState::Alarm &&
             GetWorld()->GetTimeSeconds() - LastDetectionTime > 0.6f)
    {
        SecurityState = EDerClueSecurityState::Warning;
    }
    else if (SecurityState == EDerClueSecurityState::Warning &&
             GetWorld()->GetTimeSeconds() - LastDetectionTime >= AlertMemorySeconds)
    {
        SecurityState = EDerClueSecurityState::Normal;
        ReturnToNearestPatrolNode();
    }
}

void ADerClueRuntimeDirector::UpdateAlarmPresentation()
{
    const bool bAlarmActive = SecurityState == EDerClueSecurityState::Alarm ||
                              SecurityState == EDerClueSecurityState::Lockdown;
    const float Pulse = 0.5f + 0.5f * FMath::Sin(GetWorld()->GetTimeSeconds() * 9.0f);
    for (UPointLightComponent* Light : AlarmLights)
    {
        if (!Light)
        {
            continue;
        }
        Light->SetIntensity(bAlarmActive ? FMath::Lerp(900.0f, 3200.0f, Pulse) : 120.0f);
    }
}

void ADerClueRuntimeDirector::UpdateCameras(float DeltaSeconds)
{
    const float Period = FMath::Max(0.1f, CameraSweepPeriod);
    const float Phase = GetWorld()->GetTimeSeconds() * 2.0f * PI / Period;
    for (AActor* Camera : SecurityCameras)
    {
        if (!Camera)
        {
            continue;
        }
        FRotator Rotation = CameraBaseRotations.FindRef(Camera);
        Rotation.Yaw += FMath::Sin(Phase) * CameraSweepHalfAngle;
        Camera->SetActorRotation(Rotation);
    }
    for (AActor* Visual : CameraVisuals)
    {
        if (!Visual || SecurityCameras.IsEmpty())
        {
            continue;
        }
        AActor* NearestCamera = SecurityCameras[0];
        float BestDistance = FVector::DistSquared(Visual->GetActorLocation(), NearestCamera->GetActorLocation());
        for (AActor* Camera : SecurityCameras)
        {
            const float Distance = FVector::DistSquared(Visual->GetActorLocation(), Camera->GetActorLocation());
            if (Distance < BestDistance)
            {
                BestDistance = Distance;
                NearestCamera = Camera;
            }
        }
        Visual->SetActorRotation(NearestCamera->GetActorRotation());
    }
}

bool ADerClueRuntimeDirector::Interact(ACharacter* Character, AActor* Target)
{
    if (!Character || !Target)
    {
        return false;
    }
    if (UDerClueSmartObjectComponent* SmartObject = Target->FindComponentByClass<UDerClueSmartObjectComponent>())
    {
        const bool bResult = SmartObject->Interact(Character);
        if (bResult && SmartObject->Kind == EDerClueSmartObjectKind::SecurityPanel)
        {
            for (AActor* Camera : SecurityCameras)
            {
                TArray<USpotLightComponent*> Lights;
                Camera->GetComponents(Lights);
                for (USpotLightComponent* Light : Lights)
                {
                    Light->SetVisibility(false);
                }
            }
            SecurityState = EDerClueSecurityState::Normal;
            bCamerasPowered = false;
        }
        return bResult;
    }
    return false;
}
