#include "DerClueRuntimeDirector.h"

#include "AIController.h"
#include "Blueprint/AIBlueprintHelperLibrary.h"
#include "DerClueSmartObjectComponent.h"
#include "DerCluePlanningWidget.h"
#include "Engine/OverlapResult.h"
#include "Engine/SpotLight.h"
#include "EngineUtils.h"
#include "GameFramework/Character.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Kismet/GameplayStatics.h"
#include "NavigationSystem.h"
#include "NavigationPath.h"
#include "Components/CapsuleComponent.h"
#include "Components/SpotLightComponent.h"
#include "Components/PointLightComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/StaticMeshActor.h"
#include "DrawDebugHelpers.h"
#include "InputCoreTypes.h"
#include "Navigation/PathFollowingComponent.h"
#include "Engine/StaticMesh.h"
#include "Materials/MaterialInterface.h"
#include "Camera/CameraActor.h"
#include "Components/InputComponent.h"
#include "Engine/Engine.h"
#include "Camera/CameraComponent.h"
#include "Perception/AIPerceptionComponent.h"
#include "Perception/AIPerceptionSystem.h"
#include "Perception/AISenseConfig_Hearing.h"
#include "Perception/AISenseConfig_Sight.h"
#include "Perception/AISense_Hearing.h"
#include "Perception/AISense_Sight.h"

ADerClueRuntimeDirector::ADerClueRuntimeDirector()
{
    PrimaryActorTick.bCanEverTick = true;
    PrimaryActorTick.TickInterval = 1.0f / 30.0f;

    // Default to the authored panel as a soft reference: it costs no load at
    // construction, keeps the actor working without per-level wiring, and stays
    // overridable per instance in the level.
    PlanningWidgetClass = TSoftClassPtr<UDerCluePlanningWidget>(
        FSoftObjectPath(TEXT("/Game/DerClue/UI/WBP_PlanningPanel.WBP_PlanningPanel_C")));
}

void ADerClueRuntimeDirector::BeginPlay()
{
    Super::BeginPlay();
    // Every play session starts clean; T explicitly opts into diagnostics.
    bTechnicalOverlay = false;
    DiscoverLevelActors();
    EnsureCoreActors();
    ConfigureCharacter(Guard);
    ConfigureCharacter(Thief);
    ConfigureGuardPerception();
    ConfigureWorldAndSmartObjects();
    CacheAuthoredLevelBounds();
    PositionPatrolNodesAcrossLevel();
    ConfigureVisionLights();
    CreatePrototypeTestObjects();
    ConfigureDioramaCamera();
    ConfigureViewCameras();
    CaptureMissionSnapshot();
    CreatePlanningWidget();
    SimulationEpochSeconds = GetWorld()->GetTimeSeconds();
    ReturnToNearestPatrolNode();
}

void ADerClueRuntimeDirector::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);
    RefreshPlayableThief();
    UpdateViewCamera(DeltaSeconds);
    UpdateCameras(DeltaSeconds);
    UpdateVision();
    UpdateSmartObjects();
    UpdateNoiseDevice();
    UpdatePatrol();
    UpdateMissionState();
    UpdateRoutePlanning();
    if (!bPatrolRouteCacheReady && GetWorld()->GetTimeSeconds() >= NextPatrolRouteCacheAttempt)
    {
        RebuildPatrolRouteCache();
    }
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
    if (MissionState == EDerClueMissionState::InProgress && bHasLoot)
    {
        if (!bObjectiveNotificationShown && GEngine)
        {
            bObjectiveNotificationShown = true;
            GEngine->AddOnScreenDebugMessage(7713, 3.0f, FColor::Green,
                TEXT("OBJECTIVE ACQUIRED - RETURN TO BASE"));
        }
        if (FVector::Dist2D(Thief->GetActorLocation(), BaseLocation) <= BaseReturnRadius)
        {
            MissionState = EDerClueMissionState::Success;
            if (GEngine)
            {
                GEngine->AddOnScreenDebugMessage(7714, 5.0f, FColor::Green,
                    TEXT("MISSION SUCCESS"));
            }
        }
    }
}

void ADerClueRuntimeDirector::DrawVisionFootprint(const AActor* Source, float Range,
    float FullAngleDegrees, const FColor& Color) const
{
    // Compiled out of the shipped game entirely. This costs 24 line traces per
    // source per frame -- for the guard plus every powered camera -- which is
    // affordable while authoring on a desktop and is not something a phone
    // should be spending its battery on.
#if !UE_BUILD_SHIPPING
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
        if (Guard && SecurityCameras.Contains(Source))
        {
            Params.AddIgnoredActor(Guard);
        }
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
#endif
}

void ADerClueRuntimeDirector::CacheAuthoredLevelBounds()
{
    AuthoredLevelBounds = FBox(ForceInit);
    for (TActorIterator<AStaticMeshActor> It(GetWorld()); It; ++It)
    {
        AStaticMeshActor* Actor = *It;
        if (!Actor || Actor->IsHidden() || Actor->ActorHasTag(CameraVisualTag) ||
            Actor->ActorHasTag(SecurityCameraTag) || Actor->ActorHasTag(AlarmLightTag) ||
            Actor->ActorHasTag(TEXT("DerClue.ExitLight")) || Actor->ActorHasTag(TEXT("ArcSegment")))
        {
            continue;
        }
        FVector Origin;
        FVector Extent;
        Actor->GetActorBounds(false, Origin, Extent);
        AuthoredLevelBounds += FBox::BuildAABB(Origin, Extent);
    }
}

void ADerClueRuntimeDirector::PositionPatrolNodesAcrossLevel()
{
    if (!AuthoredLevelBounds.IsValid || PatrolNodes.Num() != 4)
    {
        return;
    }
    const FVector Min = AuthoredLevelBounds.Min;
    const FVector Max = AuthoredLevelBounds.Max;
    const FVector Size = AuthoredLevelBounds.GetSize();
    const float Inset = FMath::Min(PatrolCornerInset,
        FMath::Min(Size.X, Size.Y) * 0.22f);
    const float NavigationZ = Guard ? Guard->GetActorLocation().Z : Min.Z + 100.0f;
    const FVector Candidates[4] =
    {
        FVector(Min.X + Inset, Min.Y + Inset, NavigationZ),
        FVector(Max.X - Inset, Min.Y + Inset, NavigationZ),
        FVector(Max.X - Inset, Max.Y - Inset, NavigationZ),
        FVector(Min.X + Inset, Max.Y - Inset, NavigationZ)
    };

    UNavigationSystemV1* Navigation = UNavigationSystemV1::GetCurrent(GetWorld());
    for (int32 Index = 0; Index < 4; ++Index)
    {
        FVector Destination = Candidates[Index];
        FNavLocation Projected;
        if (Navigation && Navigation->ProjectPointToNavigation(
            Candidates[Index], Projected, FVector(300.0f, 300.0f, 400.0f)))
        {
            Destination = Projected.Location;
        }
        if (USceneComponent* Root = PatrolNodes[Index]->GetRootComponent())
        {
            Root->SetMobility(EComponentMobility::Movable);
        }
        PatrolNodes[Index]->SetActorLocation(Destination);
    }
    bPatrolRouteCacheReady = false;
    NextPatrolRouteCacheAttempt = 0.0f;
}

void ADerClueRuntimeDirector::RebuildPatrolRouteCache()
{
    PatrolRoutePolyline.Reset();
    NextPatrolRouteCacheAttempt = GetWorld()->GetTimeSeconds() + 0.5f;
    if (PatrolNodes.Num() < 2)
    {
        return;
    }

    bool bEverySegmentValid = true;
    for (int32 Index = 0; Index < PatrolNodes.Num(); ++Index)
    {
        const AActor* StartNode = PatrolNodes[Index];
        const AActor* EndNode = PatrolNodes[(Index + 1) % PatrolNodes.Num()];
        if (!StartNode || !EndNode)
        {
            bEverySegmentValid = false;
            continue;
        }

        UNavigationPath* Segment = UNavigationSystemV1::FindPathToLocationSynchronously(
            this, StartNode->GetActorLocation(), EndNode->GetActorLocation(), Guard);
        if (!Segment || !Segment->IsValid() || Segment->IsPartial() || Segment->PathPoints.Num() < 2)
        {
            bEverySegmentValid = false;
            continue;
        }

        for (const FVector& Point : Segment->PathPoints)
        {
            if (PatrolRoutePolyline.IsEmpty() ||
                !PatrolRoutePolyline.Last().Equals(Point, 1.0f))
            {
                PatrolRoutePolyline.Add(Point);
            }
        }
    }
    bPatrolRouteCacheReady = bEverySegmentValid && PatrolRoutePolyline.Num() > 1;
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

    // The patrol overlay was drawing every frame regardless of the technical
    // overlay toggle: a polyline plus a 12-segment sphere per node, forever.
#if !UE_BUILD_SHIPPING
    if (bShowPatrolRoute && PatrolRoutePolyline.Num() > 1)
    {
        for (int32 Index = 1; Index < PatrolRoutePolyline.Num(); ++Index)
        {
            const FVector A = PatrolRoutePolyline[Index - 1] + FVector(0, 0, 12);
            const FVector B = PatrolRoutePolyline[Index] + FVector(0, 0, 12);
            DrawDebugLine(GetWorld(), A, B, FColor::Cyan, false, 0.0f, 0, 3.0f);
        }
        for (AActor* Node : PatrolNodes)
        {
            if (Node)
            {
                DrawDebugSphere(GetWorld(), Node->GetActorLocation() + FVector(0, 0, 12),
                    18.0f, 12, FColor::Cyan, false, 0.0f, 0, 2.0f);
            }
        }
    }
#endif

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
    if (GEngine)
    {
        const UEnum* SecurityEnum = StaticEnum<EDerClueSecurityState>();
        const UEnum* MissionEnum = StaticEnum<EDerClueMissionState>();
        GEngine->AddOnScreenDebugMessage(7711, 0.0f, FColor::White,
            FString::Printf(TEXT("TECHNICAL [T]  CYAN=PATROL  YELLOW=GUARD  RED=CAMERA  Security: %s  Mission: %s  Loot: %s"),
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
    ACharacter* TaggedThief = Found.Num() > 0 ? Cast<ACharacter>(Found[0]) : nullptr;
    ACharacter* PlayerCharacter = UGameplayStatics::GetPlayerCharacter(this, 0);
    Thief = PlayerCharacter && PlayerCharacter != Guard ? PlayerCharacter : TaggedThief;
    if (TaggedThief && TaggedThief != Thief)
    {
        // The old cinematic thief duplicated the player and looked like a second idle guard.
        TaggedThief->SetActorHiddenInGame(true);
        TaggedThief->SetActorEnableCollision(false);
        TaggedThief->SetActorTickEnabled(false);
    }
    Found.Reset();
    UGameplayStatics::GetAllActorsWithTag(this, PatrolNodeTag, Found);
    Found.Sort([](const AActor& A, const AActor& B)
    {
        const auto ReadOrder = [](const AActor& Actor)
        {
            if (Actor.Tags.Num() > 1)
            {
                const FString ExplicitOrder = Actor.Tags[1].ToString();
                if (ExplicitOrder.IsNumeric())
                {
                    return FCString::Atoi(*ExplicitOrder);
                }
            }
            FString Label = Actor.GetActorNameOrLabel();
            FString Prefix;
            FString Suffix;
            if (Label.Split(TEXT("_"), &Prefix, &Suffix, ESearchCase::IgnoreCase,
                ESearchDir::FromEnd) && Suffix.IsNumeric())
            {
                return FCString::Atoi(*Suffix);
            }
            return MAX_int32;
        };
        const int32 AOrder = ReadOrder(A);
        const int32 BOrder = ReadOrder(B);
        return AOrder == BOrder
            ? A.GetActorNameOrLabel() < B.GetActorNameOrLabel()
            : AOrder < BOrder;
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

void ADerClueRuntimeDirector::ConfigureGuardPerception()
{
    if (!GuardController)
    {
        return;
    }
    GuardPerception = GuardController->FindComponentByClass<UAIPerceptionComponent>();
    const bool bCreatedPerception = GuardPerception == nullptr;
    if (!GuardPerception)
    {
        GuardPerception = NewObject<UAIPerceptionComponent>(GuardController,
            TEXT("DerClueGuardPerception"));
    }
    GuardHearingConfig = NewObject<UAISenseConfig_Hearing>(GuardPerception,
        TEXT("DerClueGuardHearing"));
    GuardHearingConfig->HearingRange = 1400.0f;
    GuardHearingConfig->DetectionByAffiliation.bDetectEnemies = true;
    GuardHearingConfig->DetectionByAffiliation.bDetectFriendlies = true;
    GuardHearingConfig->DetectionByAffiliation.bDetectNeutrals = true;
    GuardPerception->ConfigureSense(*GuardHearingConfig);

    // Sight runs through the same perception component as hearing instead of a
    // parallel cone test, so gaining and losing the thief arrives as a stimulus
    // with engine-side line of sight, peripheral angle and target memory.
    GuardSightConfig = NewObject<UAISenseConfig_Sight>(GuardPerception,
        TEXT("DerClueGuardSight"));
    GuardSightConfig->SightRadius = GuardVisionRange;
    // A small hysteresis band: losing sight must not flicker on the exact edge
    // of the acquisition radius.
    GuardSightConfig->LoseSightRadius = GuardVisionRange * 1.1f;
    // The engine expects the half angle measured from forward, while
    // GuardVisionAngle is authored as the full cone width.
    GuardSightConfig->PeripheralVisionAngleDegrees = GuardVisionAngle * 0.5f;
    GuardSightConfig->DetectionByAffiliation.bDetectEnemies = true;
    GuardSightConfig->DetectionByAffiliation.bDetectFriendlies = true;
    GuardSightConfig->DetectionByAffiliation.bDetectNeutrals = true;
    // Nothing here assigns teams, so every actor is neutral and the affiliation
    // flags above are what make the thief visible at all.
    GuardSightConfig->SetMaxAge(0.0f);
    GuardPerception->ConfigureSense(*GuardSightConfig);

    GuardPerception->SetDominantSense(UAISense_Sight::StaticClass());
    GuardPerception->OnTargetPerceptionUpdated.RemoveDynamic(
        this, &ADerClueRuntimeDirector::HandleGuardPerception);
    GuardPerception->OnTargetPerceptionUpdated.AddDynamic(
        this, &ADerClueRuntimeDirector::HandleGuardPerception);
    if (bCreatedPerception)
    {
        GuardController->SetPerceptionComponent(*GuardPerception);
        GuardPerception->RegisterComponent();
    }
    // The perception system only accepts sense configuration from a listener it
    // has already registered; asking before that logs "Listener must have a
    // valid id to update its sense config" and the sense silently stays at its
    // defaults. Re-apply once the component is guaranteed to be registered.
    GuardPerception->ConfigureSense(*GuardHearingConfig);
    GuardPerception->ConfigureSense(*GuardSightConfig);
    GuardPerception->RequestStimuliListenerUpdate();
}

void ADerClueRuntimeDirector::HandleGuardPerception(AActor* Actor, FAIStimulus Stimulus)
{
    const TSubclassOf<UAISense> SenseClass =
        UAIPerceptionSystem::GetSenseClassForStimulus(this, Stimulus);

    // Sight: the engine decides gain and loss, including line of sight and the
    // peripheral angle. Only the thief drives pursuit; other actors are noise.
    if (SenseClass == UAISense_Sight::StaticClass())
    {
        if (Actor && Actor == Thief)
        {
            bGuardHasVisualOnThief = Stimulus.WasSuccessfullySensed();
            if (bGuardHasVisualOnThief)
            {
                // The stimulus carries where the thief was actually seen, which
                // is what the guard is allowed to know after contact is lost.
                InvestigationLocation = Stimulus.StimulusLocation;
            }
        }
        return;
    }

    if (!Stimulus.WasSuccessfullySensed() || Stimulus.Tag != TEXT("DoorNoise") ||
        bConfirmedIntrusion)
    {
        return;
    }
    SecurityState = EDerClueSecurityState::Warning;
    InvestigateLocation(Stimulus.StimulusLocation);
    if (GEngine)
    {
        GEngine->AddOnScreenDebugMessage(7712, 2.5f, FColor::Yellow,
            TEXT("DOOR NOISE: guard investigates"));
    }
}

void ADerClueRuntimeDirector::CreatePrototypeTestObjects()
{
    // These two props used to be spawned here from an engine cube, which meant
    // the level shown in the editor was not the level that ran. They are now
    // placed actors, found by tag like every other authored object, so their
    // position, scale and collision are edited in the viewport instead of in
    // code. Placed level geometry is authoritative; nothing here rewrites it.
    TArray<AActor*> Found;
    UGameplayStatics::GetAllActorsWithTag(this, TEXT("DerClue.NoiseDevice"), Found);
    NoiseDevice = Found.IsEmpty() ? nullptr : Cast<AStaticMeshActor>(Found[0]);
    if (!NoiseDevice)
    {
        UE_LOG(LogTemp, Warning,
            TEXT("DerClue: no actor tagged DerClue.NoiseDevice; the N key test has no source."));
    }

    Found.Reset();
    UGameplayStatics::GetAllActorsWithTag(this, TEXT("DerClue.CameraOcclusionTest"), Found);
    CameraOcclusionBox = Found.IsEmpty() ? nullptr : Cast<AStaticMeshActor>(Found[0]);
}


void ADerClueRuntimeDirector::UpdateNoiseDevice()
{
    if (!NoiseDevice || !Thief || !Guard || bConfirmedIntrusion)
    {
        return;
    }
    const float Now = GetWorld()->GetTimeSeconds();
    const bool bInside = FVector::Dist2D(Thief->GetActorLocation(), NoiseDevice->GetActorLocation()) <= NoiseDeviceTriggerRadius;
    const APlayerController* PlayerController = GetWorld()->GetFirstPlayerController();
    const bool bManualTrigger = PlayerController && PlayerController->WasInputKeyJustPressed(EKeys::N);
    if ((bManualTrigger || (bInside && !bThiefInsideNoiseRadius)) && Now >= NextNoiseDeviceTime)
    {
        SecurityState = EDerClueSecurityState::Warning;
        InvestigateLocation(NoiseDevice->GetActorLocation());
        NextNoiseDeviceTime = Now + NoiseDeviceCooldown;
        if (GEngine)
        {
            GEngine->AddOnScreenDebugMessage(7712, 2.0f, FColor::Yellow,
                TEXT("NOISE: guard investigates the alarm clock"));
        }
    }
    bThiefInsideNoiseRadius = bInside;
}

void ADerClueRuntimeDirector::ConfigureDioramaCamera()
{
    if (!bUseFixedDioramaCamera || !GetWorld())
    {
        return;
    }
    APlayerController* PlayerController = GetWorld()->GetFirstPlayerController();
    if (!PlayerController)
    {
        return;
    }
    FBox LevelBounds(ForceInit);
    for (TActorIterator<AStaticMeshActor> It(GetWorld()); It; ++It)
    {
        AStaticMeshActor* Actor = *It;
        if (!Actor || Actor->IsHidden() || !Actor->GetStaticMeshComponent() ||
            !Actor->GetStaticMeshComponent()->IsVisible())
        {
            continue;
        }
        FVector Origin;
        FVector Extent;
        Actor->GetActorBounds(false, Origin, Extent);
        LevelBounds += FBox::BuildAABB(Origin, Extent);
    }
    FVector Centre = LevelBounds.IsValid ? LevelBounds.GetCenter() : FVector::ZeroVector;
    FVector Extent = LevelBounds.IsValid ? LevelBounds.GetExtent() : FVector(1500.0f, 900.0f, 150.0f);
    if (!LevelBounds.IsValid)
    {
        for (AActor* Node : PatrolNodes)
        {
            Centre += Node ? Node->GetActorLocation() : FVector::ZeroVector;
        }
        if (!PatrolNodes.IsEmpty())
        {
            Centre /= static_cast<float>(PatrolNodes.Num());
        }
    }

    // Approach only along the short axis. This keeps the long side of the
    // board horizontal instead of presenting the level corner-on.
    const bool bLongAxisIsX = Extent.X >= Extent.Y;
    const FVector ApproachAxis = bLongAxisIsX
        ? FVector(0.0f, -1.0f, 0.0f)
        : FVector(-1.0f, 0.0f, 0.0f);
    // Keep the view predominantly top-down. The clamp also corrects older map
    // instances that may still contain the previous, much larger distance.
    const float CameraDistance = FMath::Min(FixedDioramaCameraDistance,
        FixedDioramaCameraHeight * 0.45f);
    const FVector CameraLocation = Centre + ApproachAxis * CameraDistance +
        FVector::UpVector * FixedDioramaCameraHeight;
    const FRotator CameraRotation = FRotationMatrix::MakeFromX(Centre - CameraLocation).Rotator();
    DioramaCamera = GetWorld()->SpawnActor<ACameraActor>(CameraLocation, CameraRotation);
    if (DioramaCamera)
    {
        if (UCameraComponent* CameraComponent = DioramaCamera->GetCameraComponent())
        {
            CameraComponent->ProjectionMode = ECameraProjectionMode::Orthographic;
            constexpr float TargetAspect = 16.0f / 9.0f;
            const FRotationMatrix CameraBasis(CameraRotation);
            const FVector ScreenRight = CameraBasis.GetUnitAxis(EAxis::Y);
            const FVector ScreenUp = CameraBasis.GetUnitAxis(EAxis::Z);
            float HalfScreenWidth = 0.0f;
            float HalfScreenHeight = 0.0f;
            for (int32 XSign : {-1, 1})
            {
                for (int32 YSign : {-1, 1})
                {
                    for (int32 ZSign : {-1, 1})
                    {
                        const FVector CornerDelta(
                            Extent.X * static_cast<float>(XSign),
                            Extent.Y * static_cast<float>(YSign),
                            Extent.Z * static_cast<float>(ZSign));
                        HalfScreenWidth = FMath::Max(HalfScreenWidth,
                            FMath::Abs(FVector::DotProduct(CornerDelta, ScreenRight)));
                        HalfScreenHeight = FMath::Max(HalfScreenHeight,
                            FMath::Abs(FVector::DotProduct(CornerDelta, ScreenUp)));
                    }
                }
            }
            CameraComponent->SetOrthoWidth(
                FMath::Max(HalfScreenWidth * 2.0f, HalfScreenHeight * 2.0f * TargetAspect) *
                FixedDioramaCameraMargin);
            CameraComponent->bConstrainAspectRatio = true;
            CameraComponent->AspectRatio = TargetAspect;
        }
        PlayerController->SetViewTargetWithBlend(DioramaCamera, 0.15f,
            VTBlend_Cubic, 0.0f, true);
    }
}

void ADerClueRuntimeDirector::CreatePlanningWidget()
{
    APlayerController* PlayerController = GetWorld()->GetFirstPlayerController();
    if (!PlayerController || PlanningWidget)
    {
        return;
    }
    // Resolve the authored panel; without it there is nothing to bind against.
    UClass* WidgetClass = PlanningWidgetClass.LoadSynchronous();
    if (!WidgetClass)
    {
        UE_LOG(LogTemp, Warning,
            TEXT("DerClue: PlanningWidgetClass is unset, planning panel skipped."));
        return;
    }
    PlanningWidget = CreateWidget<UDerCluePlanningWidget>(PlayerController, WidgetClass);
    if (PlanningWidget)
    {
        PlanningWidget->SetDirector(this);
        PlanningWidget->AddToViewport(50);
        RefreshPlanningWidget();
    }
}

void ADerClueRuntimeDirector::CaptureMissionSnapshot()
{
    if (Thief)
    {
        ThiefStartTransform = Thief->GetActorTransform();
        BaseLocation = ThiefStartTransform.GetLocation();
    }
    if (Guard)
    {
        GuardStartTransform = Guard->GetActorTransform();
    }
    MissionObjectSnapshot.Reset();
    for (UDerClueSmartObjectComponent* Object : SmartObjects)
    {
        if (!Object)
        {
            continue;
        }
        FDerClueSmartObjectSnapshot Snapshot;
        Snapshot.Object = Object;
        Snapshot.bLocked = Object->bLocked;
        Snapshot.bOpen = Object->bOpen;
        Snapshot.bPowered = Object->bPowered;
        Snapshot.bCollected = Object->bCollected;
        MissionObjectSnapshot.Add(Snapshot);
    }
}

void ADerClueRuntimeDirector::RestoreMissionSnapshot()
{
    if (APlayerController* PlayerController = GetWorld()->GetFirstPlayerController())
    {
        PlayerController->StopMovement();
    }
    if (GuardController)
    {
        GuardController->StopMovement();
    }
    if (Thief)
    {
        Thief->TeleportTo(ThiefStartTransform.GetLocation(),
            ThiefStartTransform.Rotator(), false, true);
        ConfigureCharacter(Thief);
    }
    if (Guard)
    {
        Guard->TeleportTo(GuardStartTransform.GetLocation(),
            GuardStartTransform.Rotator(), false, true);
        ConfigureCharacter(Guard);
    }
    for (const FDerClueSmartObjectSnapshot& Snapshot : MissionObjectSnapshot)
    {
        if (UDerClueSmartObjectComponent* Object = Snapshot.Object.Get())
        {
            Object->RestoreState(Snapshot.bLocked, Snapshot.bOpen,
                Snapshot.bPowered, Snapshot.bCollected);
        }
    }
    for (AActor* Camera : SecurityCameras)
    {
        TArray<USpotLightComponent*> Lights;
        Camera->GetComponents(Lights);
        for (USpotLightComponent* Light : Lights)
        {
            Light->SetVisibility(true);
        }
    }
    MissionState = EDerClueMissionState::InProgress;
    SecurityState = EDerClueSecurityState::Normal;
    bHasLoot = false;
    bObjectiveNotificationShown = false;
    bConfirmedIntrusion = false;
    bCameraHadContact = false;
    bCamerasPowered = true;
    bThiefInsideNoiseRadius = false;
    NextNoiseDeviceTime = 0.0f;
    NextMoveRequestTime = 0.0f;
    CurrentPatrolIndex = 0;
    GuardActivity = EDerClueGuardActivity::Patrol;
    SimulationEpochSeconds = GetWorld()->GetTimeSeconds();
    ReturnToNearestPatrolNode();
}

void ADerClueRuntimeDirector::ToggleRouteRecording()
{
    bSuppressNextRecordedClick = true;
    if (RouteMode == EDerClueRouteMode::Recording)
    {
        RouteMode = EDerClueRouteMode::Ready;
    }
    else
    {
        RecordedDestinations.Reset();
        RestoreMissionSnapshot();
        RouteMode = EDerClueRouteMode::Recording;
    }
    RefreshPlanningWidget();
}

void ADerClueRuntimeDirector::PlayRecordedRoute()
{
    if (RecordedDestinations.IsEmpty() || RouteMode == EDerClueRouteMode::Recording)
    {
        return;
    }
    bSuppressNextRecordedClick = true;
    RestoreMissionSnapshot();
    PlaybackDestinationIndex = 0;
    bPlaybackMoveIssued = false;
    RouteMode = EDerClueRouteMode::Playing;
    RefreshPlanningWidget();
}

void ADerClueRuntimeDirector::UpdateRoutePlanning()
{
    APlayerController* PlayerController = GetWorld()->GetFirstPlayerController();
    if (!PlayerController || !Thief)
    {
        return;
    }

    if (RouteMode == EDerClueRouteMode::Recording &&
        PlayerController->WasInputKeyJustPressed(EKeys::LeftMouseButton))
    {
        if (bSuppressNextRecordedClick)
        {
            bSuppressNextRecordedClick = false;
        }
        else
        {
            FHitResult Hit;
            if (PlayerController->GetHitResultUnderCursor(ECC_Visibility, true, Hit))
            {
                FNavLocation Projected;
                if (UNavigationSystemV1* Nav = UNavigationSystemV1::GetCurrent(GetWorld());
                    Nav && Nav->ProjectPointToNavigation(Hit.ImpactPoint, Projected))
                {
                    if (RecordedDestinations.IsEmpty() ||
                        FVector::DistSquared2D(RecordedDestinations.Last(), Projected.Location) > FMath::Square(20.0f))
                    {
                        RecordedDestinations.Add(Projected.Location);
                        RefreshPlanningWidget();
                    }
                }
            }
        }
    }

    if (RouteMode != EDerClueRouteMode::Playing)
    {
        return;
    }
    if (MissionState != EDerClueMissionState::InProgress)
    {
        PlayerController->StopMovement();
        RouteMode = EDerClueRouteMode::Ready;
        RefreshPlanningWidget();
        return;
    }
    if (!RecordedDestinations.IsValidIndex(PlaybackDestinationIndex))
    {
        PlayerController->StopMovement();
        MissionState = EDerClueMissionState::Failed;
        RouteMode = EDerClueRouteMode::Ready;
        if (GEngine)
        {
            GEngine->AddOnScreenDebugMessage(7715, 4.0f, FColor::Red,
                TEXT("PLAN ENDED WITHOUT RETURNING TO BASE"));
        }
        RefreshPlanningWidget();
        return;
    }
    const FVector Destination = RecordedDestinations[PlaybackDestinationIndex];
    if (!bPlaybackMoveIssued)
    {
        UAIBlueprintHelperLibrary::SimpleMoveToLocation(PlayerController, Destination);
        bPlaybackMoveIssued = true;
    }
    if (FVector::Dist2D(Thief->GetActorLocation(), Destination) <= RecordedPointAcceptanceRadius)
    {
        ++PlaybackDestinationIndex;
        bPlaybackMoveIssued = false;
        RefreshPlanningWidget();
    }
}

void ADerClueRuntimeDirector::RefreshPlanningWidget()
{
    if (!PlanningWidget)
    {
        return;
    }
    FText RecordLabel = FText::FromString(RouteMode == EDerClueRouteMode::Recording
        ? TEXT("STOP RECORD") : TEXT("RECORD"));
    FString Status;
    switch (RouteMode)
    {
        case EDerClueRouteMode::Free:
            Status = TEXT("FREE TEST");
            break;
        case EDerClueRouteMode::Recording:
            Status = FString::Printf(TEXT("RECORDING  %d COMMANDS"), RecordedDestinations.Num());
            break;
        case EDerClueRouteMode::Ready:
            Status = FString::Printf(TEXT("READY  %d COMMANDS"), RecordedDestinations.Num());
            break;
        case EDerClueRouteMode::Playing:
            Status = FString::Printf(TEXT("PLAYING  %d/%d"),
                FMath::Max(0, PlaybackDestinationIndex + 1), RecordedDestinations.Num());
            break;
    }
    PlanningWidget->Refresh(RecordLabel, FText::FromString(Status),
        !RecordedDestinations.IsEmpty() && RouteMode != EDerClueRouteMode::Recording &&
        RouteMode != EDerClueRouteMode::Playing);
}

void ADerClueRuntimeDirector::EnsureCoreActors()
{
    if (!Guard && !PatrolNodes.IsEmpty() && GetWorld())
    {
        UClass* GuardClass = LoadClass<ACharacter>(nullptr,
            TEXT("/Game/DerClue/Blueprints/BP_GrantGuard.BP_GrantGuard_C"));
        if (GuardClass)
        {
            FActorSpawnParameters SpawnParameters;
            SpawnParameters.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AdjustIfPossibleButAlwaysSpawn;
            Guard = GetWorld()->SpawnActor<ACharacter>(GuardClass,
                PatrolNodes[0]->GetActorLocation(), PatrolNodes[0]->GetActorRotation(), SpawnParameters);
            if (Guard)
            {
                Guard->Tags.AddUnique(GuardTag);
            }
        }
    }
    if (Guard)
    {
        GuardController = Cast<AAIController>(Guard->GetController());
        if (!GuardController && GetWorld())
        {
            GuardController = GetWorld()->SpawnActor<AAIController>();
            if (GuardController)
            {
                GuardController->Possess(Guard);
            }
        }
    }
}

void ADerClueRuntimeDirector::RefreshPlayableThief()
{
    ACharacter* PlayerCharacter = UGameplayStatics::GetPlayerCharacter(this, 0);
    if (!PlayerCharacter || PlayerCharacter == Guard || PlayerCharacter == Thief)
    {
        return;
    }
    Thief = PlayerCharacter;
    ConfigureCharacter(Thief);
}

void ADerClueRuntimeDirector::ConfigureWorldAndSmartObjects()
{
    for (TActorIterator<AStaticMeshActor> It(GetWorld()); It; ++It)
    {
        AStaticMeshActor* Actor = *It;
        if (!Actor)
        {
            continue;
        }
        if (Actor->ActorHasTag(PatrolNodeTag))
        {
            // A patrol marker is annotation, not world geometry. Skipping it
            // outright left whatever collision the level happened to carry:
            // three of the four markers are full 1m cubes and were standing in
            // the patrol room as solid obstacles that both blocked the pawn and
            // punched holes in the navmesh.
            if (UPrimitiveComponent* Marker = Actor->GetStaticMeshComponent())
            {
                Marker->SetCollisionEnabled(ECollisionEnabled::NoCollision);
                Marker->SetCanEverAffectNavigation(false);
            }
            continue;
        }
        if (UPrimitiveComponent* Primitive = Actor->GetStaticMeshComponent())
        {
            const bool bVisualOnly = Actor->ActorHasTag(CameraVisualTag) ||
                Actor->ActorHasTag(SecurityCameraTag) ||
                Actor->ActorHasTag(AlarmLightTag) ||
                Actor->ActorHasTag(TEXT("DerClue.ExitLight")) ||
                Actor->ActorHasTag(TEXT("ArcSegment"));
            if (bVisualOnly)
            {
                Primitive->SetCollisionEnabled(ECollisionEnabled::NoCollision);
                Primitive->SetCanEverAffectNavigation(false);
                continue;
            }
            Primitive->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
            Primitive->SetCollisionResponseToChannel(ECC_Pawn, ECR_Block);
            Primitive->SetCollisionResponseToChannel(ECC_Visibility, ECR_Block);
            // A door is deliberately left out of the navmesh: while it counted
            // as navigation geometry, a shut door erased the doorway from the
            // graph, so no route between rooms could be planned at all and the
            // actor merely walked into the wall. Passability is owned by the
            // door's own NavModifierComponent instead (locked doors only).
            Primitive->SetCanEverAffectNavigation(!Actor->ActorHasTag(TEXT("DerClue.Door")));
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
            if (Kind == EDerClueSmartObjectKind::Door && bKeepPrototypeDoorsOpen)
            {
                Component->bLocked = false;
                Component->bOpen = true;
            }
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
        Capsule->SetCapsuleRadius(32.0f, true);
        Capsule->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
        Capsule->SetCollisionResponseToChannel(ECC_Pawn, ECR_Block);
        Capsule->SetCollisionResponseToChannel(ECC_WorldStatic, ECR_Block);
        Capsule->SetCollisionResponseToChannel(ECC_WorldDynamic, ECR_Block);
    }
    if (UCharacterMovementComponent* Movement = Character->GetCharacterMovement())
    {
        Movement->MaxWalkSpeed = Character == Guard ? GuardPatrolSpeed : ThiefMoveSpeed;
        Movement->MaxAcceleration = 700.0f;
        Movement->BrakingDecelerationWalking = 900.0f;
        if (FNavMovementProperties* NavMovement = Movement->GetNavMovementProperties())
        {
            NavMovement->bUseAccelerationForPaths = true;
        }
        Movement->bOrientRotationToMovement = true;
        Movement->RotationRate = FRotator(0.0f, 300.0f, 0.0f);
        // The player must follow the clicked path exactly. RVO is reserved for
        // the autonomous guard; enabling it on both actors makes the thief
        // oscillate or stop when avoidance velocities compete with click-to-move.
        Movement->bUseRVOAvoidance = Character == Guard;
        Movement->AvoidanceConsiderationRadius = 180.0f;
    }
}

void ADerClueRuntimeDirector::ConfigureVisionLights()
{
    if (AuthoredLevelBounds.IsValid)
    {
        const FVector LevelSize = AuthoredLevelBounds.GetSize();
        // Cameras trace farther than the complete board, so the first blocking
        // wall—not a magic radius—defines their real visible distance.
        CameraVisionRange = FVector2D(LevelSize.X, LevelSize.Y).Size() + 200.0f;
        // A guard carries a short, narrow flashlight: approximately half of
        // the room depth, independent from the surveillance camera range.
        GuardVisionRange = FMath::Clamp(FMath::Min(LevelSize.X, LevelSize.Y) * 0.52f,
            700.0f, 1300.0f);
    }
    if (Guard)
    {
        // The authored Guard_Flashlight is a standalone spotlight actor in the
        // level. Once selected, it becomes a local fixture on the moving guard;
        // keeping its old world transform would leave the beam floating ahead.
        if (!GuardFlashlight)
        {
            float BestDistanceSquared = TNumericLimits<float>::Max();
            for (TActorIterator<ASpotLight> It(GetWorld()); It; ++It)
            {
                ASpotLight* Candidate = *It;
                if (!Candidate || SecurityCameras.Contains(Candidate))
                {
                    continue;
                }
                const float DistanceSquared = FVector::DistSquared(
                    Candidate->GetActorLocation(), Guard->GetActorLocation());
                if (DistanceSquared < BestDistanceSquared)
                {
                    BestDistanceSquared = DistanceSquared;
                    GuardFlashlight = Candidate;
                }
            }
        }
        if (GuardFlashlight)
        {
            if (USpotLightComponent* Light = Cast<USpotLightComponent>(GuardFlashlight->GetLightComponent()))
            {
                Light->SetMobility(EComponentMobility::Movable);
                Light->SetVisibility(true);
                Light->SetAttenuationRadius(GuardVisionRange);
                Light->SetInnerConeAngle(GuardVisionAngle * 0.20f);
                Light->SetOuterConeAngle(GuardVisionAngle * 0.50f);
                Light->SetCastShadows(true);
            }
            GuardFlashlight->AttachToActor(Guard, FAttachmentTransformRules::SnapToTargetNotIncludingScale);
            GuardFlashlight->SetActorRelativeLocation(
                FVector(GuardFlashlightForwardOffset, 0.0f, GuardFlashlightHeight));
            GuardFlashlight->SetActorRelativeRotation(FRotator(GuardFlashlightPitch, 0.0f, 0.0f));
        }

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

    const float Now = GetWorld()->GetTimeSeconds();
    if (GuardActivity == EDerClueGuardActivity::Search)
    {
        GuardController->StopMovement();
        const float Period = FMath::Max(0.5f, InvestigationSearchPeriod);
        const float Phase = (Now - SearchStartedTime) * 2.0f * PI / Period;
        FRotator ScanRotation = Guard->GetActorRotation();
        ScanRotation.Yaw = SearchBaseYaw + FMath::Sin(Phase) * InvestigationSearchHalfAngle;
        Guard->SetActorRotation(ScanRotation);
        if (Now >= SearchEndTime)
        {
            if (bConfirmedIntrusion)
            {
                BeginIntruderSweep();
            }
            else
            {
                SecurityState = EDerClueSecurityState::Normal;
                ReturnToNearestPatrolNode();
            }
        }
        return;
    }

    if (GuardActivity == EDerClueGuardActivity::Patrol && IsPatrolNodeOccupied(PatrolNodes[CurrentPatrolIndex]))
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

    const bool bUsesPatrolNodeGoal = GuardActivity == EDerClueGuardActivity::Patrol ||
        GuardActivity == EDerClueGuardActivity::IntruderSweep;
    const bool bRespondingToPoint = !bUsesPatrolNodeGoal;
    const FVector Goal = bRespondingToPoint
        ? InvestigationLocation
        : PatrolNodes[CurrentPatrolIndex]->GetActorLocation();
    if (FVector::Dist2D(Guard->GetActorLocation(), Goal) <= PatrolAcceptanceRadius)
    {
        if (bRespondingToPoint)
        {
            GuardController->StopMovement();
            GuardActivity = EDerClueGuardActivity::Search;
            SecurityState = bConfirmedIntrusion
                ? EDerClueSecurityState::Alarm
                : EDerClueSecurityState::Warning;
            SearchStartedTime = Now;
            SearchEndTime = Now + InvestigationSearchDuration;
            SearchBaseYaw = Guard->GetActorRotation().Yaw;
        }
        else
        {
            do
            {
                CurrentPatrolIndex = (CurrentPatrolIndex + 1) % PatrolNodes.Num();
            }
            while (GuardActivity == EDerClueGuardActivity::Patrol &&
                   PatrolNodes.Num() > 1 && IsPatrolNodeOccupied(PatrolNodes[CurrentPatrolIndex]));
            RequestMove(PatrolNodes[CurrentPatrolIndex]->GetActorLocation());
        }
        return;
    }

    if (GuardController->GetMoveStatus() != EPathFollowingStatus::Moving)
    {
        if (!RequestMove(Goal) && bUsesPatrolNodeGoal)
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

        if (SmartObject->Kind == EDerClueSmartObjectKind::Door && bKeepPrototypeDoorsOpen)
        {
            SmartObject->SetOpen(true);
        }
        else if (SmartObject->Kind == EDerClueSmartObjectKind::Door && Nearest <= SmartObject->InteractionRadius)
        {
            if (!SmartObject->bOpen)
            {
                SmartObject->SetOpen(true);
                // Only an opening caused by the thief becomes an external
                // hearing stimulus. A guard never investigates its own door.
                if (Thief && ThiefDistance <= GuardDistance)
                {
                    SmartObject->EmitNoise(SmartObject->GetOwner());
                }
            }
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
                if (!bConfirmedIntrusion)
                {
                    SecurityState = EDerClueSecurityState::Normal;
                }
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
            bool bAnySafeExists = false;
            bool bAnySafeOpen = false;
            for (UDerClueSmartObjectComponent* Candidate : SmartObjects)
            {
                if (Candidate && Candidate->Kind == EDerClueSmartObjectKind::Safe)
                {
                    bAnySafeExists = true;
                    bAnySafeOpen |= Candidate->bOpen;
                }
            }
            if ((!bAnySafeExists || bAnySafeOpen) && SmartObject->Interact(Thief))
            {
                bHasLoot = true;
            }
        }
        else if (SmartObject->Kind == EDerClueSmartObjectKind::Extraction &&
                 Thief && ThiefDistance <= SmartObject->InteractionRadius && bHasLoot &&
                 MissionState == EDerClueMissionState::InProgress &&
                 FVector::Dist2D(Thief->GetActorLocation(), BaseLocation) <= BaseReturnRadius)
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
            UNavigationPath* Path = UNavigationSystemV1::FindPathToLocationSynchronously(
                GetWorld(), Guard->GetActorLocation(),
                Projected.Location, Guard);
            if (!Path || !Path->IsValid() || Path->IsPartial())
            {
                continue;
            }
            const float Distance = static_cast<float>(Path->GetPathLength());
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
    GuardActivity = EDerClueGuardActivity::Investigate;
    InvestigationLocation = WorldLocation;
    if (Guard && Guard->GetCharacterMovement())
    {
        Guard->GetCharacterMovement()->MaxWalkSpeed = GuardInvestigationSpeed;
    }
    if (GuardController)
    {
        GuardController->StopMovement();
    }
    NextMoveRequestTime = 0.0f;
    RequestMove(WorldLocation);
}

void ADerClueRuntimeDirector::ReturnToNearestPatrolNode()
{
    if (bConfirmedIntrusion)
    {
        BeginIntruderSweep();
        return;
    }
    GuardActivity = EDerClueGuardActivity::Patrol;
    if (Guard && Guard->GetCharacterMovement())
    {
        Guard->GetCharacterMovement()->MaxWalkSpeed = GuardPatrolSpeed;
    }
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

void ADerClueRuntimeDirector::BeginIntruderSweep()
{
    bConfirmedIntrusion = true;
    GuardActivity = EDerClueGuardActivity::IntruderSweep;
    SecurityState = EDerClueSecurityState::Alarm;
    if (Guard && Guard->GetCharacterMovement())
    {
        Guard->GetCharacterMovement()->MaxWalkSpeed = GuardIntruderSweepSpeed;
    }
    const int32 Nearest = FindNearestReachablePatrolNode();
    if (Nearest != INDEX_NONE)
    {
        CurrentPatrolIndex = Nearest;
    }
    if (GuardController)
    {
        GuardController->StopMovement();
    }
    NextMoveRequestTime = 0.0f;
    if (PatrolNodes.IsValidIndex(CurrentPatrolIndex))
    {
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
    if (Guard && SecurityCameras.Contains(Source))
    {
        Params.AddIgnoredActor(Guard);
    }
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
    // Guard sight is whatever AIPerception last reported; cameras stay on the
    // explicit cone test below because they are props, not perceiving pawns.
    const bool bGuardSeesThief = Guard && bGuardHasVisualOnThief;
    bool bCameraSeesThief = false;
    if (bCamerasPowered)
    {
        for (AActor* Camera : SecurityCameras)
        {
            bCameraSeesThief |= CanSeeTarget(Camera, Thief, CameraVisionRange, CameraVisionAngle);
        }
    }

    // Direct guard sight is the only live pursuit signal. It may refresh the
    // last-seen position, but camera/noise reports never become a GPS tracker.
    if (bGuardSeesThief)
    {
        const bool bWasAlreadyPursuing = GuardActivity == EDerClueGuardActivity::Pursue;
        bConfirmedIntrusion = true;
        MissionState = EDerClueMissionState::Failed;
        SecurityState = EDerClueSecurityState::Alarm;
        GuardActivity = EDerClueGuardActivity::Pursue;
        if (Guard->GetCharacterMovement())
        {
            Guard->GetCharacterMovement()->MaxWalkSpeed = GuardInvestigationSpeed;
        }
        const FVector NewLastSeenLocation = Thief->GetActorLocation();
        if (!bWasAlreadyPursuing ||
            FVector::DistSquared2D(InvestigationLocation, NewLastSeenLocation) > FMath::Square(60.0f))
        {
            InvestigationLocation = NewLastSeenLocation;
            if (!bWasAlreadyPursuing)
            {
                GuardController->StopMovement();
                NextMoveRequestTime = 0.0f;
            }
            RequestMove(InvestigationLocation);
        }
        bCameraHadContact = bCameraSeesThief;
        return;
    }

    // Having lost direct sight, the guard checks the last place where the
    // thief was actually seen instead of continuing to know the live position.
    if (GuardActivity == EDerClueGuardActivity::Pursue)
    {
        SecurityState = bConfirmedIntrusion
            ? EDerClueSecurityState::Alarm
            : EDerClueSecurityState::Warning;
        GuardActivity = EDerClueGuardActivity::Investigate;
        NextMoveRequestTime = 0.0f;
        RequestMove(InvestigationLocation);
    }

    // A surveillance camera reports one snapshot when contact begins. While
    // contact remains continuous it does not keep steering the guard to the
    // thief's current coordinates. Reacquisition can create a fresh report.
    if (bCameraSeesThief && !bCameraHadContact && GuardActivity != EDerClueGuardActivity::Pursue)
    {
        bConfirmedIntrusion = true;
        MissionState = EDerClueMissionState::Failed;
        SecurityState = EDerClueSecurityState::Alarm;
        InvestigateLocation(Thief->GetActorLocation());
        SecurityState = EDerClueSecurityState::Alarm;
    }
    bCameraHadContact = bCameraSeesThief;
}

void ADerClueRuntimeDirector::UpdateCameras(float DeltaSeconds)
{
    // A readable stealth window is part of the level contract: the thief must
    // have enough time to move between the authored cover objects.
    const float Period = FMath::Max(14.0f, CameraSweepPeriod);
    const float Phase = (GetWorld()->GetTimeSeconds() - SimulationEpochSeconds) * 2.0f * PI / Period;
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


void ADerClueRuntimeDirector::ConfigureViewCameras()
{
    if (!GetWorld())
    {
        return;
    }

    // Level-authored viewpoints join the cycle, so more angles can be added by
    // dropping a CameraActor in the map and tagging it -- no code change.
    ExtraViewCameras.Reset();
    TArray<AActor*> Found;
    UGameplayStatics::GetAllActorsWithTag(this, TEXT("DerClue.ViewCamera"), Found);
    for (AActor* Actor : Found)
    {
        if (Actor && Actor != DioramaCamera)
        {
            ExtraViewCameras.Add(Actor);
        }
    }

    if (!InspectionCamera)
    {
        InspectionCamera = GetWorld()->SpawnActor<ACameraActor>();
        if (InspectionCamera)
        {
            if (UCameraComponent* Component = InspectionCamera->GetCameraComponent())
            {
                // Deliberately perspective: the diorama camera is orthographic,
                // which flattens faces into unreadable silhouettes.
                Component->ProjectionMode = ECameraProjectionMode::Perspective;
                Component->SetFieldOfView(70.0f);
            }
        }
    }

    if (APlayerController* PlayerController = GetWorld()->GetFirstPlayerController())
    {
        EnableInput(PlayerController);
        if (InputComponent)
        {
            InputComponent->BindKey(EKeys::C, IE_Pressed, this,
                &ADerClueRuntimeDirector::CycleViewMode);
        }
    }
    SetViewIndex(0);
}

void ADerClueRuntimeDirector::CycleViewMode()
{
    SetViewIndex(ViewIndex + 1);
}

void ADerClueRuntimeDirector::SetViewIndex(int32 NewIndex)
{
    const int32 BuiltInCount = 5;
    const int32 Total = BuiltInCount + ExtraViewCameras.Num();
    ViewIndex = ((NewIndex % Total) + Total) % Total;
    if (ViewIndex < BuiltInCount)
    {
        ViewMode = static_cast<EDerClueViewMode>(ViewIndex);
    }

    FString Label;
    if (ViewIndex >= BuiltInCount)
    {
        const AActor* Camera = ExtraViewCameras[ViewIndex - BuiltInCount];
        Label = FString::Printf(TEXT("Level camera: %s"),
            Camera ? *Camera->GetActorNameOrLabel() : TEXT("<none>"));
    }
    else
    {
        static const TCHAR* Names[] = { TEXT("Top-down diorama"),
            TEXT("Over the thief's shoulder"), TEXT("Thief, front view"),
            TEXT("Guard, front view"), TEXT("Pawn's own camera") };
        Label = Names[ViewIndex];
    }
    if (GEngine)
    {
        GEngine->AddOnScreenDebugMessage(1701, 3.0f, FColor::Cyan,
            FString::Printf(TEXT("[C] View %d/%d  -  %s"),
                ViewIndex + 1, Total, *Label));
    }
}

void ADerClueRuntimeDirector::AimInspectionCamera(const AActor* Subject, bool bFromFront)
{
    if (!InspectionCamera || !Subject)
    {
        return;
    }
    const FVector Base = Subject->GetActorLocation();
    const FVector Forward = Subject->GetActorForwardVector();
    const FVector Right = Subject->GetActorRightVector();

    FVector Location;
    FVector LookAt;
    if (bFromFront)
    {
        Location = Base + Forward * FaceCameraDistance + FVector::UpVector * FaceCameraHeight;
        LookAt = Base + FVector::UpVector * FaceCameraHeight;
    }
    else
    {
        Location = Base - Forward * ShoulderCameraDistance +
            Right * ShoulderCameraSideOffset + FVector::UpVector * ShoulderCameraHeight;
        LookAt = Base + Forward * 500.0f + FVector::UpVector * (ShoulderCameraHeight * 0.8f);
    }
    InspectionCamera->SetActorLocationAndRotation(Location,
        FRotationMatrix::MakeFromX(LookAt - Location).Rotator());
}

void ADerClueRuntimeDirector::UpdateViewCamera(float DeltaSeconds)
{
    APlayerController* PlayerController = GetWorld() ? GetWorld()->GetFirstPlayerController() : nullptr;
    if (!PlayerController)
    {
        return;
    }

    AActor* Desired = nullptr;
    if (ViewIndex >= 5)
    {
        Desired = ExtraViewCameras.IsValidIndex(ViewIndex - 5)
            ? ExtraViewCameras[ViewIndex - 5].Get() : nullptr;
    }
    else
    {
        switch (ViewMode)
        {
        case EDerClueViewMode::Diorama:
            Desired = bUseFixedDioramaCamera ? DioramaCamera : nullptr;
            break;
        case EDerClueViewMode::OverShoulder:
            AimInspectionCamera(Thief, false);
            Desired = Thief ? InspectionCamera : nullptr;
            break;
        case EDerClueViewMode::ThiefFace:
            AimInspectionCamera(Thief, true);
            Desired = Thief ? InspectionCamera : nullptr;
            break;
        case EDerClueViewMode::GuardFace:
            AimInspectionCamera(Guard, true);
            Desired = Guard ? InspectionCamera : nullptr;
            break;
        case EDerClueViewMode::PawnCamera:
            Desired = PlayerController->GetPawn();
            break;
        }
    }

    // Falling back to the pawn keeps the screen usable if a subject is missing
    // rather than leaving the view pinned to whatever was last shown.
    if (!Desired)
    {
        Desired = PlayerController->GetPawn();
    }
    if (Desired && PlayerController->GetViewTarget() != Desired)
    {
        PlayerController->SetViewTargetWithBlend(Desired, 0.2f);
    }
}
