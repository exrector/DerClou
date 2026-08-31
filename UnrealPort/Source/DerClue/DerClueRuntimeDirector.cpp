#include "DerClueRuntimeDirector.h"

#include "AIController.h"
#include "Blueprint/AIBlueprintHelperLibrary.h"
#include "DerClueSmartObjectComponent.h"
#include "DerCluePlanningWidget.h"
#include "Engine/OverlapResult.h"
#include "Engine/SpotLight.h"
#include "EngineUtils.h"
#include "GameFramework/Character.h"
#include "Engine/DebugCameraController.h"
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
#include "DerClueSmartObjectMenu.h"
#include "Animation/AnimSequence.h"
#include "Animation/Skeleton.h"
#include "Engine/SkeletalMesh.h"
#include "TimerManager.h"
#include "Engine/Engine.h"
#include "Camera/CameraComponent.h"
#include "Perception/AIPerceptionComponent.h"
#include "Perception/AIPerceptionSystem.h"
#include "Perception/AISenseConfig_Hearing.h"
#include "Perception/AISenseConfig_Sight.h"
#include "Perception/AISense_Hearing.h"
#include "Perception/AISense_Sight.h"
#include "Components/StateTreeAIComponent.h"
#include "StateTree.h"

ADerClueRuntimeDirector::ADerClueRuntimeDirector()
{
    PrimaryActorTick.bCanEverTick = true;
    PrimaryActorTick.TickInterval = 1.0f / 30.0f;

    // Default to the authored panel as a soft reference: it costs no load at
    // construction, keeps the actor working without per-level wiring, and stays
    // overridable per instance in the level.
    SmartObjectMenuClass = UDerClueSmartObjectMenu::StaticClass();
    // A revolver, not the futuristic first-person gun. It matters beyond looks:
    // the Interaction pack ships genuinely ONE-HANDED revolver animations, so
    // the weapon and the poses below finally agree with each other. Every
    // pistol animation found anywhere else in the project is two-handed, which
    // is why the guard kept holding an invisible second grip.
    GuardWeaponMesh = TSoftObjectPtr<USkeletalMesh>(FSoftObjectPath(
        TEXT("/Game/Interaction/Weapons/Revolver/Meshes/SK_Revolver.SK_Revolver")));
    // Both were rifle poses before: two hands on the weapon, left arm raised to
    // a foregrip that a revolver does not have. A_Revolver_Stand is the real
    // one-handed ready stance, so the left arm hangs by itself with no bone
    // masking needed in the AnimBP.
    PistolEquipAnim = TSoftObjectPtr<UAnimSequence>(FSoftObjectPath(
        TEXT("/Game/Interaction/Animations/Revolver/A_Revolver_Stand.A_Revolver_Stand")));
    PistolAimAnim = TSoftObjectPtr<UAnimSequence>(FSoftObjectPath(
        TEXT("/Game/Interaction/Animations/Revolver/A_Revolver_Stand.A_Revolver_Stand")));
    // A complete, non-additive shot on the stock mannequin skeleton. The
    // robot explicitly lists that skeleton as compatible; MM_Pistol_Fire is
    // additive and must never be played as a standalone pose.
    PistolFireAnim = TSoftObjectPtr<UAnimSequence>(FSoftObjectPath(
        TEXT("/Game/Interaction/Animations/Revolver/Shoot/Rev_Shoot_F.Rev_Shoot_F")));
    GuardWalkWeaponAnim = TSoftObjectPtr<UAnimSequence>(FSoftObjectPath(
        TEXT("/Game/SciFiCharacterPack/SciFiSoldier/Animations/Walk_Fwd_Rifle_Ironsights.Walk_Fwd_Rifle_Ironsights")));
    GuardJogWeaponAnim = TSoftObjectPtr<UAnimSequence>(FSoftObjectPath(
        TEXT("/Game/SciFiCharacterPack/SciFiSoldier/Animations/Jog_Fwd_Rifle.Jog_Fwd_Rifle")));
    GuardRunWeaponAnim = TSoftObjectPtr<UAnimSequence>(FSoftObjectPath(
        TEXT("/Game/SciFiCharacterPack/SciFiSoldier/Animations/Sprint_Fwd_Rifle.Sprint_Fwd_Rifle")));
    GuardIdleWeaponAnim = TSoftObjectPtr<UAnimSequence>(FSoftObjectPath(
        TEXT("/Game/SciFiCharacterPack/SciFiSoldier/Animations/Idle_Rifle_Hip.Idle_Rifle_Hip")));
    // Shot from the front, so he goes over backwards.
    ThiefDeathAnim = TSoftObjectPtr<UAnimSequence>(FSoftObjectPath(
        TEXT("/Game/Characters/Mannequins/Anims/Death/MM_Death_Back_01.MM_Death_Back_01")));
    PlanningWidgetClass = TSoftClassPtr<UDerCluePlanningWidget>(
        FSoftObjectPath(TEXT("/Game/DerClue/UI/WBP_PlanningPanel.WBP_PlanningPanel_C")));
    GuardStateTreeAsset = TSoftObjectPtr<UStateTree>(
        FSoftObjectPath(TEXT("/Game/DerClue/AI/ST_GuardBehavior.ST_GuardBehavior")));
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
    ConfigureWorldAndSmartObjects();
    CacheAuthoredLevelBounds();
    PositionPatrolNodesAcrossLevel();
    ConfigureVisionLights();
    // Vision ranges are finalized from the authored level before the native
    // AIPerception listener is configured. Configuring it earlier left the
    // logical sight radius different from the visible flashlight radius.
    ConfigureGuardPerception();
    ConfigureGuardBrain();
    CreatePrototypeTestObjects();
    EquipGuardWeapon();
    ConfigureDioramaCamera();
    ConfigureViewCameras();
    CaptureMissionSnapshot();
    CreatePlanningWidget();
    SimulationEpochSeconds = GetWorld()->GetTimeSeconds();
    UE_LOG(LogTemp, Display,
        TEXT("DerClue start: cameraRange=%.1f guardRange=%.1f thief=%s guard=%s noiseDevice=%s"),
        CameraVisionRange, GuardVisionRange,
        Thief ? *Thief->GetActorLocation().ToCompactString() : TEXT("missing"),
        Guard ? *Guard->GetActorLocation().ToCompactString() : TEXT("missing"),
        NoiseDevice ? *NoiseDevice->GetActorLocation().ToCompactString() : TEXT("missing"));
}

void ADerClueRuntimeDirector::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);
    RefreshPlayableThief();
    // Camera ownership is intentionally left to Unreal's native debug camera.
    // The previous custom orbit fought mouse focus, UMG and the player's view
    // target every frame.
    UpdateGuardArmPose(DeltaSeconds);
    UpdateGuardWeaponTransform();
    UpdateCameras(DeltaSeconds);
    UpdateVision();
    UpdateSmartObjects();
    UpdateSmartObjectMenu();
    UpdateNoiseDevice();
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
    const FVector GameplayAnchor = Guard && Thief
        ? (Guard->GetActorLocation() + Thief->GetActorLocation()) * 0.5f
        : FVector::ZeroVector;
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
        // The prototype level contains authoring/test objects outside the two
        // playable rooms. They are not part of the player's map and must not
        // expand the initial camera framing into an enormous empty field.
        if (Guard && Thief && FVector::Dist2D(Origin, GameplayAnchor) > 2600.0f)
        {
            continue;
        }
        AuthoredLevelBounds += FBox::BuildAABB(Origin, Extent);
    }
}

void ADerClueRuntimeDirector::PositionPatrolNodesAcrossLevel()
{
    if (PatrolNodes.Num() != 4)
    {
        return;
    }

    // Authored placement wins. This used to overwrite all four markers with the
    // corners of the whole level, which put two of them deep inside the thief's
    // room -- so the guard walked straight at the thief on the first frame of
    // every mission, and moving any furniture silently moved the patrol because
    // the corners are derived from the level bounds.
    //
    // Markers are only projected onto the navmesh now, so a route exists from
    // wherever the designer put them. The corner spread survives purely as a
    // fallback for a level whose markers were never placed apart.
    UNavigationSystemV1* NavigationSystem = UNavigationSystemV1::GetCurrent(GetWorld());
    FBox AuthoredSpread(ForceInit);
    for (AActor* Node : PatrolNodes)
    {
        if (Node)
        {
            AuthoredSpread += Node->GetActorLocation();
        }
    }
    const bool bAuthored = AuthoredSpread.IsValid &&
        AuthoredSpread.GetSize().Size2D() > 200.0f;
    if (bAuthored)
    {
        for (AActor* Node : PatrolNodes)
        {
            if (!Node)
            {
                continue;
            }
            if (USceneComponent* Root = Node->GetRootComponent())
            {
                Root->SetMobility(EComponentMobility::Movable);
            }
            FNavLocation Projected;
            if (NavigationSystem && NavigationSystem->ProjectPointToNavigation(
                Node->GetActorLocation(), Projected, FVector(300.0f, 300.0f, 400.0f)))
            {
                Node->SetActorLocation(Projected.Location);
            }
        }
        bPatrolRouteCacheReady = false;
        NextPatrolRouteCacheAttempt = 0.0f;
        return;
    }

    if (!AuthoredLevelBounds.IsValid)
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
    if (Guard && Guard->GetMesh())
    {
        // The arm pose writes bones directly, and a write only survives if it
        // lands after the mesh has evaluated its animation for the frame.
        // Without this prerequisite the director might tick first and the
        // animation would silently overwrite the pose every frame, which looks
        // exactly like the feature not working at all.
        AddTickPrerequisiteComponent(Guard->GetMesh());
        GuardArmLastYaw = Guard->GetActorRotation().Yaw;
    }
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

void ADerClueRuntimeDirector::ConfigureGuardBrain()
{
    if (!GuardController || !Guard)
    {
        return;
    }

    GuardBrain = GuardController->FindComponentByClass<UDerClueGuardBrainComponent>();
    if (!GuardBrain)
    {
        GuardBrain = NewObject<UDerClueGuardBrainComponent>(GuardController,
            TEXT("DerClueGuardBrain"));
        GuardController->AddInstanceComponent(GuardBrain);
        GuardBrain->RegisterComponent();
    }

    FDerClueGuardTuning Tuning;
    Tuning.AcceptanceRadius = PatrolAcceptanceRadius;
    Tuning.OccupiedNodeRadius = OccupiedNodeRadius;
    Tuning.RepathCooldown = RepathCooldown;
    Tuning.PatrolSpeed = GuardPatrolSpeed;
    Tuning.InvestigationSpeed = GuardInvestigationSpeed;
    Tuning.PursuitSpeed = GuardPursuitSpeed;
    Tuning.SweepSpeed = GuardIntruderSweepSpeed;
    Tuning.PursuitStoppingDistance = GuardShootDistance;
    Tuning.SearchDuration = InvestigationSearchDuration;
    Tuning.SearchHalfAngle = InvestigationSearchHalfAngle;
    Tuning.SearchPeriod = InvestigationSearchPeriod;
    GuardBrain->Initialize(GuardController, Guard, Thief, PatrolNodes, Tuning);
    GuardBrain->OnActivityChanged.RemoveDynamic(
        this, &ADerClueRuntimeDirector::HandleGuardActivityChanged);
    GuardBrain->OnActivityChanged.AddDynamic(
        this, &ADerClueRuntimeDirector::HandleGuardActivityChanged);

    GuardStateTreeComponent = GuardController->FindComponentByClass<UStateTreeAIComponent>();
    if (!GuardStateTreeComponent)
    {
        GuardStateTreeComponent = NewObject<UStateTreeAIComponent>(GuardController,
            TEXT("DerClueGuardStateTree"));
        GuardStateTreeComponent->SetStartLogicAutomatically(false);
        GuardController->AddInstanceComponent(GuardStateTreeComponent);
        GuardStateTreeComponent->RegisterComponent();
    }
    GuardBrain->SetStateTreeComponent(GuardStateTreeComponent);

    UStateTree* StateTree = GuardStateTreeAsset.LoadSynchronous();
    if (!StateTree || !StateTree->IsReadyToRun())
    {
        UE_LOG(LogTemp, Error,
            TEXT("DerClue: guard StateTree is missing or not compiled; guard brain fallback is active."));
        GuardBrain->ResetToPatrol();
        return;
    }

    if (GuardStateTreeComponent->IsRunning())
    {
        GuardStateTreeComponent->StopLogic(TEXT("DerClue reconfigure"));
    }
    GuardStateTreeComponent->SetStateTree(StateTree);
    GuardStateTreeComponent->StartLogic();
    GuardBrain->ResetToPatrol();
    UE_LOG(LogTemp, Display, TEXT("DerClue: native guard StateTree started."));
}

void ADerClueRuntimeDirector::HandleGuardActivityChanged(EDerClueGuardActivity Activity)
{
    if (Activity == EDerClueGuardActivity::Patrol && !bConfirmedIntrusion)
    {
        SecurityState = EDerClueSecurityState::Normal;
    }
    else if (Activity == EDerClueGuardActivity::Investigate ||
             Activity == EDerClueGuardActivity::Search)
    {
        SecurityState = bConfirmedIntrusion
            ? EDerClueSecurityState::Alarm
            : EDerClueSecurityState::Warning;
    }
    else if (Activity == EDerClueGuardActivity::Pursue ||
             Activity == EDerClueGuardActivity::IntruderSweep)
    {
        SecurityState = EDerClueSecurityState::Alarm;
    }
    if (!bKillSequenceStarted)
    {
        PlayGuardActivityAnimation(Activity);
    }
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
            const bool bSensed = Stimulus.WasSuccessfullySensed();
            const bool bPreviouslySensed = GuardBrain && GuardBrain->HasVisualOnThief();
            if (bSensed)
            {
                bGuardHasAcquiredThief = true;
            }
            if (GuardBrain)
            {
                GuardBrain->ReportSight(bSensed, Stimulus.StimulusLocation);
            }
            if (bPreviouslySensed != bSensed)
            {
                UE_LOG(LogTemp, Display,
                    TEXT("DerClue perception: guard sight %s thief at %s"),
                    bSensed ? TEXT("ACQUIRED") : TEXT("LOST"),
                    *Stimulus.StimulusLocation.ToCompactString());
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
    UE_LOG(LogTemp, Display, TEXT("DerClue perception: DoorNoise at %s"),
        *Stimulus.StimulusLocation.ToCompactString());
    if (GuardBrain)
    {
        GuardBrain->ReportNoise(Stimulus.StimulusLocation);
    }
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
    // Entering the radius is an event. Merely beginning the mission while
    // already inside it is not; otherwise BeginPlay manufactures a noise that
    // the player never caused. Retry uses the same baseline rule below.
    bNoiseDeviceBaselineInitialized = NoiseDevice && Thief;
    bThiefInsideNoiseRadius = bNoiseDeviceBaselineInitialized &&
        FVector::Dist2D(Thief->GetActorLocation(), NoiseDevice->GetActorLocation()) <=
            NoiseDeviceTriggerRadius;

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
    // Actor BeginPlay ordering is not guaranteed. If the player pawn became
    // available after the device was discovered, establish the overlap state
    // first and do not turn that initial state into a fabricated noise event.
    if (!bNoiseDeviceBaselineInitialized)
    {
        bThiefInsideNoiseRadius = bInside;
        bNoiseDeviceBaselineInitialized = true;
        return;
    }
    if ((bManualTrigger || (bInside && !bThiefInsideNoiseRadius)) && Now >= NextNoiseDeviceTime)
    {
        SecurityState = EDerClueSecurityState::Warning;
        UE_LOG(LogTemp, Display, TEXT("DerClue perception: NoiseDevice %s at %s"),
            bManualTrigger ? TEXT("manual") : TEXT("entered"),
            *NoiseDevice->GetActorLocation().ToCompactString());
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
        // Remember the authored framing so orbiting is a modification of it
        // rather than a replacement: pressing C back to Diorama returns to a
        // view that still frames the level the way it was designed to.
        DioramaCentre = Centre;
        DioramaDefaultCentre = Centre;
        DioramaBaseOffset = CameraLocation - Centre;
        DioramaOrbitYaw = DioramaBaseOffset.Rotation().Yaw;
        DioramaOrbitPitch = FMath::Clamp(CameraRotation.Pitch,
            DioramaOrbitMinPitch, DioramaOrbitMaxPitch);
        DioramaDefaultYaw = DioramaOrbitYaw;
        DioramaDefaultPitch = DioramaOrbitPitch;
        DioramaOrbitRadius = FVector(DioramaBaseOffset.X, DioramaBaseOffset.Y, 0.0f).Size();
        DioramaCameraHeight = FMath::Max(100.0f, DioramaBaseOffset.Z);
        DioramaDefaultCameraHeight = DioramaCameraHeight;
        DioramaZoom = 1.0f;
        if (const UCameraComponent* Component = DioramaCamera->GetCameraComponent())
        {
            DioramaBaseOrthoWidth = Component->OrthoWidth;
        }
        bDioramaOrbitReady = true;

        PlayerController->SetViewTargetWithBlend(DioramaCamera, 0.15f,
            VTBlend_Cubic, 0.0f, true);

        // The inspection view starts at human eye level beside the guard, not
        // kilometres above the map. It is only the launch point for Unreal's
        // native free debug camera, so the user can immediately inspect hands,
        // weapons and feet and then fly anywhere.
        if (Guard)
        {
            const FVector EyeTarget = Guard->GetActorLocation() + FVector::UpVector * 70.0f;
            const FVector InspectionStartLocation = EyeTarget - Guard->GetActorForwardVector() * 360.0f +
                Guard->GetActorRightVector() * 180.0f + FVector::UpVector * 10.0f;
            DioramaCamera->SetActorLocationAndRotation(InspectionStartLocation,
                FRotationMatrix::MakeFromX(EyeTarget - InspectionStartLocation).Rotator());
            if (UCameraComponent* CameraComponent = DioramaCamera->GetCameraComponent())
            {
                CameraComponent->ProjectionMode = ECameraProjectionMode::Perspective;
                CameraComponent->SetFieldOfView(65.0f);
                CameraComponent->bConstrainAspectRatio = false;
            }
        }
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
        if (USkeletalMeshComponent* Mesh = Thief->GetMesh())
        {
            ThiefMeshStartRelativeTransform = Mesh->GetRelativeTransform();
            ThiefMeshStartCollisionProfile = Mesh->GetCollisionProfileName();
        }
        BaseLocation = ThiefStartTransform.GetLocation();
        // An authored extraction marker wins over the spawn point, so the place
        // the mission is handed in is something visible in the level that the
        // designer can move, not an invisible radius around wherever the thief
        // happened to appear.
        {
            TArray<AActor*> ExtractionActors;
            UGameplayStatics::GetAllActorsWithTag(this, TEXT("Extraction"), ExtractionActors);
            if (!ExtractionActors.IsEmpty() && ExtractionActors[0])
            {
                BaseLocation = ExtractionActors[0]->GetActorLocation();
            }
        }
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
    GetWorldTimerManager().ClearTimer(PistolStepTimer);
    GetWorldTimerManager().ClearTimer(KillStepTimer);
    bKillSequenceStarted = false;
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
        if (USkeletalMeshComponent* Mesh = Thief->GetMesh())
        {
            Mesh->SetAllBodiesSimulatePhysics(false);
            Mesh->SetSimulatePhysics(false);
            Mesh->PutAllRigidBodiesToSleep();
            Mesh->AttachToComponent(Thief->GetCapsuleComponent(),
                FAttachmentTransformRules::KeepRelativeTransform);
            Mesh->SetRelativeTransform(ThiefMeshStartRelativeTransform);
            if (!ThiefMeshStartCollisionProfile.IsNone())
            {
                Mesh->SetCollisionProfileName(ThiefMeshStartCollisionProfile);
            }
        }
        if (UCapsuleComponent* Capsule = Thief->GetCapsuleComponent())
        {
            Capsule->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
        }
        bThiefRagdollActive = false;
        Thief->TeleportTo(ThiefStartTransform.GetLocation(),
            ThiefStartTransform.Rotator(), false, true);
        ConfigureCharacter(Thief);
        RestoreCharacterAnimationBlueprint(Thief);
        if (UCharacterMovementComponent* Movement = Thief->GetCharacterMovement())
        {
            Movement->SetMovementMode(MOVE_Walking);
        }
    }
    if (Guard)
    {
        Guard->TeleportTo(GuardStartTransform.GetLocation(),
            GuardStartTransform.Rotator(), false, true);
        ConfigureCharacter(Guard);
        RestoreCharacterAnimationBlueprint(Guard);
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
    bGuardHasAcquiredThief = false;
    bCamerasPowered = true;
    bNoiseDeviceBaselineInitialized = NoiseDevice && Thief;
    bThiefInsideNoiseRadius = bNoiseDeviceBaselineInitialized &&
        FVector::Dist2D(Thief->GetActorLocation(), NoiseDevice->GetActorLocation()) <=
            NoiseDeviceTriggerRadius;
    NextNoiseDeviceTime = 0.0f;
    SimulationEpochSeconds = GetWorld()->GetTimeSeconds();
    if (GuardBrain)
    {
        GuardBrain->ResetToPatrol();
    }
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
            if (Kind == EDerClueSmartObjectKind::Door)
            {
                // A door the thief can simply walk through carries no decision.
                // Locked by default gives the lockpick/crowbar trade something
                // to apply to; the prototype flag still forces them open.
                Component->bLocked = !bKeepPrototypeDoorsOpen;
                Component->bOpen = bKeepPrototypeDoorsOpen;
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

        // Avoidance was never actually running. bUseRVOAvoidance was assigned
        // directly, and that only flips the flag -- an agent is registered with
        // UAvoidanceManager exclusively inside SetAvoidanceEnabled(). With
        // nobody registered, two blocking capsules meeting in a corridor simply
        // wedged and neither could get past the other.
        //
        // Both actors are registered now, and who yields is expressed with the
        // engine's own weighting rather than by switching avoidance off for one
        // of them. Per the engine: actors divert course in proportion to their
        // relative weights, and at 1.0 an actor will not divert at all. So the
        // thief keeps following the clicked path exactly -- the property the
        // previous approach was trying to protect -- while the guard, being
        // autonomous, does the whole job of stepping aside.
        const bool bIsGuard = Character == Guard;

        FNavAvoidanceMask OwnGroup;
        OwnGroup.ClearAll();
        OwnGroup.SetGroup(bIsGuard ? GuardAvoidanceGroup : ThiefAvoidanceGroup);
        Movement->SetAvoidanceGroupMask(OwnGroup);

        FNavAvoidanceMask GroupsToAvoid;
        GroupsToAvoid.ClearAll();
        if (bIsGuard)
        {
            GroupsToAvoid.SetGroup(ThiefAvoidanceGroup);
        }
        Movement->SetGroupsToAvoidMask(GroupsToAvoid);

        Movement->AvoidanceConsiderationRadius = 180.0f;
        Movement->AvoidanceWeight = bIsGuard ? 0.35f : 1.0f;
        Movement->SetAvoidanceEnabled(true);
    }
}

void ADerClueRuntimeDirector::ConfigureVisionLights()
{
    if (AuthoredLevelBounds.IsValid)
    {
        const FVector LevelSize = AuthoredLevelBounds.GetSize();
        // CameraVisionRange is an authored gameplay value. It must not be
        // overwritten with the diagonal of the whole board here: doing that
        // made a room camera detect the thief at the distant spawn point and
        // start the mission in Alarm. Occlusion still uses native visibility
        // traces, so walls cap the effective range inside this authored limit.
        // A guard carries a short, narrow flashlight: approximately half of
        // the room depth, independent from the surveillance camera range.
        GuardVisionRange = FMath::Clamp(FMath::Min(LevelSize.X, LevelSize.Y) * 0.52f,
            700.0f, 1300.0f);
    }
    // A surveillance cone that stops in mid-air looks broken and plays worse:
    // the player cannot tell where it ends. Trace from each camera to the wall
    // it faces and let that be the reach. This deliberately replaces the
    // authored number, unlike the old code that silently substituted the whole
    // board's diagonal and put the spawn point under surveillance.
    // Beam length = distance to the wall the camera faces. Nothing more
    // elaborate: one ray along its own aim, and the cone ends where the room
    // ends. Walls nearer than that still cut the view per frame through the
    // visibility trace in CanSeeTarget.
    if (bCameraRangeReachesFacingWall && !SecurityCameras.IsEmpty())
    {
        float Reach = 0.0f;
        for (AActor* Camera : SecurityCameras)
        {
            if (!Camera)
            {
                continue;
            }
            const FVector Start = Camera->GetActorLocation();
            FRotator Aim = CameraBaseRotations.Contains(Camera)
                ? CameraBaseRotations.FindRef(Camera)
                : Camera->GetActorRotation();
            // Flatten the aim before measuring. A surveillance camera is tilted
            // down, so tracing along its actual forward hits the FLOOR a few
            // metres out -- that distance was being stored as the beam length,
            // which is why the cone died just under the camera instead of
            // reaching across the room. The wall it faces is a horizontal
            // question; the downward tilt is only how the cone is aimed at it.
            Aim.Pitch = 0.0f;
            Aim.Roll = 0.0f;
            FCollisionQueryParams Params(SCENE_QUERY_STAT(DerClueCameraReach), true, Camera);
            Params.AddIgnoredActor(Camera);
            if (Guard) { Params.AddIgnoredActor(Guard); }
            if (Thief) { Params.AddIgnoredActor(Thief); }
            FHitResult Hit;
            if (GetWorld()->LineTraceSingleByChannel(Hit, Start,
                Start + Aim.Vector() * 8000.0f, ECC_Visibility, Params))
            {
                Reach = FMath::Max(Reach, Hit.Distance);
            }
        }
        if (Reach > 100.0f)
        {
            CameraVisionRange = Reach;
            UE_LOG(LogTemp, Log, TEXT("[DerClue] Camera beam reaches its facing wall: %.0f cm"),
                CameraVisionRange);
        }
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
            // The guard carries keys: a locked door is an obstacle for the
            // thief, never for the patrol, which is what lets the guard keep
            // walking the whole perimeter while the thief still has to work
            // for the same doorway.
            const bool bGuardIsNearest = GuardDistance <= ThiefDistance;
            const bool bMayOpen = bGuardIsNearest || !SmartObject->bLocked;
            if (!SmartObject->bOpen && bMayOpen)
            {
                if (bGuardIsNearest)
                {
                    SmartObject->bLocked = false;
                }
                AActor* const Opener = bGuardIsNearest
                    ? static_cast<AActor*>(Guard)
                    : static_cast<AActor*>(Thief);
                if (Opener)
                {
                    SmartObject->SetSwingAwayFrom(Opener->GetActorLocation());
                }
                SmartObject->SetOpen(true);
                // Simply opening a door is silent now. Noise is the price of
                // the crowbar, not of walking through a door you already
                // unlocked -- otherwise every entry alerts the guard and the
                // choice between tools means nothing.
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

void ADerClueRuntimeDirector::InvestigateLocation(FVector WorldLocation)
{
    if (GuardBrain)
    {
        GuardBrain->ReportNoise(WorldLocation);
    }
}

void ADerClueRuntimeDirector::ReturnToNearestPatrolNode()
{
    if (GuardBrain)
    {
        GuardBrain->ResetToPatrol();
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
    FCollisionQueryParams Params(SCENE_QUERY_STAT(DerClueVision), true, Source);
    Params.AddIgnoredActor(Source);
    if (Guard && SecurityCameras.Contains(Source))
    {
        Params.AddIgnoredActor(Guard);
    }

    // Two samples, not one. Tracing only to the actor's centre meant a crate at
    // chest height never hid anyone from a camera mounted near the ceiling: the
    // sightline simply passed over it to the single point being tested, so
    // partial cover did nothing at all.
    //
    // Requiring BOTH the chest and the head to be clear is what makes "anything
    // you stand behind protects you" true, and it stays fully deterministic --
    // same position, same verdict, every run.
    const FVector Chest = Target->GetActorLocation();
    FVector Head = Chest;
    if (const ACharacter* TargetCharacter = Cast<ACharacter>(Target))
    {
        if (const UCapsuleComponent* Capsule = TargetCharacter->GetCapsuleComponent())
        {
            Head.Z = Chest.Z + Capsule->GetScaledCapsuleHalfHeight() * 0.8f;
        }
    }
    else
    {
        Head.Z = Chest.Z + 60.0f;
    }

    for (const FVector& Sample : { Chest, Head })
    {
        FHitResult Hit;
        const bool bBlocked = GetWorld()->LineTraceSingleByChannel(
            Hit, SourceLocation, Sample, ECC_Visibility, Params) &&
            Hit.GetActor() != Target;
        if (bBlocked)
        {
            return false;
        }
    }
    return true;
}

void ADerClueRuntimeDirector::UpdateVision()
{
    if (!Thief)
    {
        return;
    }
    // Guard sight is whatever AIPerception last reported; cameras stay on the
    // explicit cone test below because they are props, not perceiving pawns.
    const bool bGuardSeesThief = Guard && GuardBrain && GuardBrain->HasVisualOnThief();
    bool bCameraSeesThief = false;
    AActor* DetectingCamera = nullptr;
    if (bCamerasPowered)
    {
        for (AActor* Camera : SecurityCameras)
        {
            if (CanSeeTarget(Camera, Thief, CameraVisionRange, CameraVisionAngle))
            {
                bCameraSeesThief = true;
                DetectingCamera = Camera;
                break;
            }
        }
    }

    // AIPerception's cone may briefly report LOST while the guard turns at the
    // end of MoveTo. That must not make a stationary or retreating thief
    // immune. After a real visual acquisition, distance plus an unobstructed
    // 360-degree close-range trace is the capture condition; BeginKillSequence
    // rotates the guard toward the target before the shot.
    if (Guard && bGuardHasAcquiredThief && !bKillSequenceStarted &&
        FVector::Dist2D(Guard->GetActorLocation(), Thief->GetActorLocation()) <=
            GuardShootDistance + 35.0f &&
        CanSeeTarget(Guard, Thief, GuardShootDistance + 50.0f, 360.0f))
    {
        BeginKillSequence();
        return;
    }

    // Direct guard sight is the only live pursuit signal. It may refresh the
    // last-seen position, but camera/noise reports never become a GPS tracker.
    if (bGuardSeesThief)
    {
        bConfirmedIntrusion = true;
        SecurityState = EDerClueSecurityState::Alarm;
        bCameraHadContact = bCameraSeesThief;

        // Being seen is no longer instant failure. The guard has to cross the
        // room first, which is the window the thief gets to break line of
        // sight -- and it is what makes the sighting readable instead of a
        // sudden loss with no visible cause.
        const float Distance = FVector::Dist2D(Guard->GetActorLocation(), Thief->GetActorLocation());
        if (Distance > GuardShootDistance && !bKillSequenceStarted)
        {
            // Pursuit is the brain's state to own; the director only reports
            // what was seen. Speed and stopping distance live in the brain's
            // native MoveTo request.
            if (GuardBrain)
            {
                GuardBrain->ReportSight(true, Thief->GetActorLocation());
            }
        }
        else if (!bKillSequenceStarted)
        {
            BeginKillSequence();
        }
        return;
    }

    // A surveillance camera reports one snapshot when contact begins. While
    // contact remains continuous it does not keep steering the guard to the
    // thief's current coordinates. Reacquisition can create a fresh report.
    if (bCameraSeesThief && !bCameraHadContact)
    {
        UE_LOG(LogTemp, Display,
            TEXT("DerClue perception: camera %s ACQUIRED thief at %s (range=%.1f)"),
            DetectingCamera ? *DetectingCamera->GetName() : TEXT("unknown"),
            *Thief->GetActorLocation().ToCompactString(), CameraVisionRange);
        bConfirmedIntrusion = true;
        MissionState = EDerClueMissionState::Failed;
        SecurityState = EDerClueSecurityState::Alarm;
        if (GuardBrain)
        {
            GuardBrain->ReportCameraContact(Thief->GetActorLocation());
        }
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
            InputComponent->BindKey(EKeys::G, IE_Pressed, this,
                &ADerClueRuntimeDirector::GuardDrawAndFire);
            InputComponent->BindKey(EKeys::One, IE_Pressed, this,
                &ADerClueRuntimeDirector::TriggerAction1);
            InputComponent->BindKey(EKeys::Two, IE_Pressed, this,
                &ADerClueRuntimeDirector::TriggerAction2);
            InputComponent->BindKey(EKeys::Three, IE_Pressed, this,
                &ADerClueRuntimeDirector::TriggerAction3);
        }
    }
    if (APlayerController* PlayerController = GetWorld()->GetFirstPlayerController())
    {
        // The native debug camera expects ordinary game input. UMG focus and a
        // permanently visible cursor were the reason mouse-look felt broken.
        PlayerController->SetInputMode(FInputModeGameOnly());
        PlayerController->bShowMouseCursor = false;
    }
    SetViewIndex(0);

#if !UE_BUILD_SHIPPING
    // Use the engine's own free-flight inspection controller. Simulation keeps
    // running; RMB/mouse looks, WASD flies, Q/E changes altitude and the wheel
    // changes flight speed. No custom camera math remains in control of Play.
    TWeakObjectPtr<APlayerController> WeakPlayerController =
        GetWorld()->GetFirstPlayerController();
    GetWorldTimerManager().SetTimerForNextTick([WeakPlayerController]()
    {
        if (APlayerController* Controller = WeakPlayerController.Get())
        {
            Controller->ConsoleCommand(TEXT("ToggleDebugCamera"), true);
            if (GEngine)
            {
                GEngine->AddOnScreenDebugMessage(1702, 8.0f, FColor::Cyan,
                    TEXT("FREE CAMERA: mouse look | WASD move | Q/E height | wheel speed | F8 return"));
            }
        }
    });
#endif
}

void ADerClueRuntimeDirector::CycleViewMode()
{
    SetViewIndex(ViewIndex + 1);
}

void ADerClueRuntimeDirector::SetViewIndex(int32 NewIndex)
{
    const int32 BuiltInCount = 6;
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
            TEXT("Guard, front view"), TEXT("Pawn's own camera"),
            TEXT("Free - director hands off") };
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
        Location = Base + Forward * (FaceCameraDistance * InspectionZoom) +
            FVector::UpVector * FaceCameraHeight;
        LookAt = Base + FVector::UpVector * FaceCameraHeight;
    }
    else
    {
        Location = Base - Forward * (ShoulderCameraDistance * InspectionZoom) +
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

    // One observer camera, no preset roulette. It orbits the complete level at
    // all times while gameplay continues underneath it.
    AActor* Desired = DioramaCamera.Get();
    if (!Desired)
    {
        Desired = PlayerController->GetPawn().Get();
    }
    ViewIndex = 0;
    ViewMode = EDerClueViewMode::Diorama;
    UpdateDioramaOrbit(PlayerController);

    // Only when the choice itself changes. Re-asserting it every frame is what
    // made every external camera tool unusable.
    if (Desired && Desired != LastAppliedViewTarget.Get())
    {
        PlayerController->SetViewTargetWithBlend(Desired, 0.2f);
        LastAppliedViewTarget = Desired;
    }
}


void ADerClueRuntimeDirector::UpdateDioramaOrbit(APlayerController* PlayerController)
{
    if (!bDioramaOrbitReady || !DioramaCamera || !PlayerController)
    {
        return;
    }

    // Right button, not left: left remains click-to-move. Capturing the mouse
    // in GameOnly mode while dragging makes relative mouse delta reliable even
    // when the planning UMG panel or visible cursor previously had focus.
    const bool bRightMouseDown = PlayerController->IsInputKeyDown(EKeys::RightMouseButton);
    if (bRightMouseDown && !bDioramaOrbitDragging)
    {
        bDioramaOrbitDragging = true;
        PlayerController->bShowMouseCursor = false;
        PlayerController->SetInputMode(FInputModeGameOnly());
    }
    if (bRightMouseDown)
    {
        float MouseX = 0.0f;
        float MouseY = 0.0f;
        PlayerController->GetInputMouseDelta(MouseX, MouseY);
        DioramaOrbitYaw += MouseX * DioramaOrbitSensitivity;
        DioramaCameraHeight = FMath::Clamp(
            DioramaCameraHeight - MouseY * 18.0f, 100.0f, 6000.0f);
    }
    else if (bDioramaOrbitDragging)
    {
        bDioramaOrbitDragging = false;
        FInputModeGameAndUI InputMode;
        InputMode.SetHideCursorDuringCapture(false);
        InputMode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);
        PlayerController->SetInputMode(InputMode);
        PlayerController->bShowMouseCursor = true;
    }

    // Keyboard fallback is valuable in PIE because a visible cursor or a UMG
    // panel can consume mouse capture. It also allows precise inspection while
    // the simulation continues running.
    const float OrbitStep = 75.0f * GetWorld()->GetDeltaSeconds();
    if (PlayerController->IsInputKeyDown(EKeys::Left))
    {
        DioramaOrbitYaw -= OrbitStep;
    }
    if (PlayerController->IsInputKeyDown(EKeys::Right))
    {
        DioramaOrbitYaw += OrbitStep;
    }
    const float WheelDelta = PlayerController->GetInputAnalogKeyState(EKeys::MouseWheelAxis);
    const bool bZoomIn = WheelDelta > KINDA_SMALL_NUMBER ||
        PlayerController->WasInputKeyJustPressed(EKeys::MouseScrollUp);
    const bool bZoomOut = WheelDelta < -KINDA_SMALL_NUMBER ||
        PlayerController->WasInputKeyJustPressed(EKeys::MouseScrollDown);
    if (bZoomIn || bZoomOut)
    {
        // Intersect the cursor ray with the gameplay floor before changing the
        // orthographic width. Moving the orbit centre by the inverse scale
        // delta keeps that exact floor point under the cursor: zoom-to-cursor,
        // not zoom-to-the-middle-of-the-level.
        FVector CursorOrigin;
        FVector CursorDirection;
        FVector CursorFloorPoint = DioramaCentre;
        bool bHasCursorFloorPoint = false;
        if (PlayerController->DeprojectMousePositionToWorld(CursorOrigin, CursorDirection) &&
            !FMath::IsNearlyZero(CursorDirection.Z))
        {
            const float FloorZ = AuthoredLevelBounds.IsValid
                ? AuthoredLevelBounds.Min.Z + 2.0f
                : 0.0f;
            const float T = (FloorZ - CursorOrigin.Z) / CursorDirection.Z;
            if (T >= 0.0f)
            {
                CursorFloorPoint = CursorOrigin + CursorDirection * T;
                bHasCursorFloorPoint = true;
            }
        }

        const float OldZoom = DioramaZoom;
        DioramaZoom = FMath::Clamp(DioramaZoom * (bZoomIn ? 0.82f : 1.18f),
            0.025f, 4.0f);
        if (bHasCursorFloorPoint && OldZoom > KINDA_SMALL_NUMBER &&
            !FMath::IsNearlyEqual(OldZoom, DioramaZoom))
        {
            const float ScaleRatio = DioramaZoom / OldZoom;
            FVector CursorDelta = CursorFloorPoint - DioramaCentre;
            CursorDelta.Z = 0.0f;
            DioramaCentre += CursorDelta * (1.0f - ScaleRatio);
        }
    }

    // Yaw circles the level; height is an independent, literal world-space
    // control. This is what makes Up/Down raise and lower the observer instead
    // of merely tilting a camera that remains stuck in the sky.
    const FVector HorizontalOffset =
        FRotator(0.0f, DioramaOrbitYaw, 0.0f).Vector() * DioramaOrbitRadius;
    const FVector Location = DioramaCentre + HorizontalOffset +
        FVector::UpVector * DioramaCameraHeight;
    DioramaCamera->SetActorLocationAndRotation(Location,
        FRotationMatrix::MakeFromX(DioramaCentre - Location).Rotator());

    if (UCameraComponent* Component = DioramaCamera->GetCameraComponent())
    {
        if (Component->ProjectionMode == ECameraProjectionMode::Orthographic &&
            DioramaBaseOrthoWidth > 0.0f)
        {
            Component->SetOrthoWidth(DioramaBaseOrthoWidth * DioramaZoom);
        }
    }
}

void ADerClueRuntimeDirector::ResetDioramaView()
{
    DioramaCentre = DioramaDefaultCentre;
    DioramaOrbitYaw = DioramaDefaultYaw;
    DioramaOrbitPitch = DioramaDefaultPitch;
    DioramaCameraHeight = DioramaDefaultCameraHeight;
    DioramaZoom = 1.0f;
    SetViewIndex(0);
}

void ADerClueRuntimeDirector::RaiseDioramaCamera()
{
    DioramaCameraHeight = FMath::Clamp(DioramaCameraHeight + 180.0f, 100.0f, 6000.0f);
}

void ADerClueRuntimeDirector::LowerDioramaCamera()
{
    DioramaCameraHeight = FMath::Clamp(DioramaCameraHeight - 180.0f, 100.0f, 6000.0f);
}

void ADerClueRuntimeDirector::UpdateGuardArmPose(float DeltaSeconds)
{
    if (!bOverrideGuardArmPose || !Guard)
    {
        return;
    }

    USkeletalMeshComponent* Mesh = Guard->GetMesh();
    if (!Mesh || !Mesh->GetSkeletalMeshAsset())
    {
        return;
    }

    // Two sine waves whose periods do not divide into each other, so the arm
    // never returns to exactly the same place on a fixed beat.
    GuardArmSwayPhase += DeltaSeconds * GuardArmSwaySpeed;
    const float SwayYaw = FMath::Sin(GuardArmSwayPhase) * GuardArmSwayYaw;
    const float SwayPitch = FMath::Sin(GuardArmSwayPhase * 1.7f) * GuardArmSwayPitch;

    // The arm lags the body through a turn. Without this the beam is welded to
    // the chest and the guard reads as a turret rather than someone looking
    // around with a light in his hand.
    const float Yaw = Guard->GetActorRotation().Yaw;
    const float YawDelta = FMath::FindDeltaAngleDegrees(GuardArmLastYaw, Yaw);
    GuardArmLastYaw = Yaw;
    GuardArmTurnLag = FMath::FInterpTo(GuardArmTurnLag + YawDelta, 0.0f, DeltaSeconds, 3.0f);
    const float FollowYaw = FMath::Clamp(-GuardArmTurnLag * GuardArmFollowTurn, -35.0f, 35.0f);

    // Component space, not world: these are the bone's own local axes, which is
    // what the pose values above are expressed in.
    const FRotator UpperArm(GuardUpperArmPose.Pitch + SwayPitch,
                            GuardUpperArmPose.Yaw + SwayYaw + FollowYaw,
                            GuardUpperArmPose.Roll);

    // Written after the mesh has evaluated its animation this frame, so the
    // body animation still plays and only these three bones are replaced.
    // Order matters: parent before child, or the child inherits a stale parent.
    Mesh->SetBoneRotationByName(TEXT("upperarm_r"), UpperArm, EBoneSpaces::ComponentSpace);
    Mesh->SetBoneRotationByName(TEXT("lowerarm_r"), GuardLowerArmPose, EBoneSpaces::ComponentSpace);
    if (!GuardHandPose.IsNearlyZero())
    {
        Mesh->SetBoneRotationByName(TEXT("hand_r"), GuardHandPose, EBoneSpaces::ComponentSpace);
    }
}

void ADerClueRuntimeDirector::UpdateGuardWeaponTransform()
{
    if (!Guard || !GuardWeapon || !Guard->GetMesh())
    {
        return;
    }

    // Position follows the animated right hand, while orientation follows the
    // guard. WeaponGripRotation carries the correction from the hand bone's
    // axes to the weapon mesh's own; it was dialled for the old first-person
    // gun and may need re-dialling now that the mesh is SK_Revolver, whose
    // authored barrel axis has not been verified.
    // Both position AND orientation now come from the animated right hand.
    // Taking the rotation from the actor instead was why the weapon only ever
    // looked right while aiming: aiming happens to align body and hand, so the
    // error was invisible exactly when it was easiest to check, and the gun sat
    // crooked in every other pose.
    const USkeletalMeshComponent* Mesh = Guard->GetMesh();
    const FTransform HandTransform = Mesh->GetSocketTransform(TEXT("hand_r"), RTS_World);
    GuardWeapon->SetWorldLocation(HandTransform.GetLocation());
    GuardWeapon->SetWorldRotation(HandTransform.GetRotation() * WeaponGripRotation.Quaternion());
    // SK_Revolver is authored at real sidearm scale, so unlike the oversized
    // first-person gun it needs no shrinking to read as a pistol in the hand.
    GuardWeapon->SetWorldScale3D(FVector(1.0f));
}




void ADerClueRuntimeDirector::UpdateSmartObjectMenu()
{
    APlayerController* PlayerController = GetWorld() ? GetWorld()->GetFirstPlayerController() : nullptr;
    if (!PlayerController || !Thief)
    {
        return;
    }
    if (!SmartObjectMenu)
    {
        UClass* MenuClass = SmartObjectMenuClass.LoadSynchronous();
        if (!MenuClass)
        {
            return;
        }
        SmartObjectMenu = CreateWidget<UDerClueSmartObjectMenu>(PlayerController, MenuClass);
        if (!SmartObjectMenu)
        {
            return;
        }
        SmartObjectMenu->SetDirector(this);
        SmartObjectMenu->AddToViewport(8);
    }

    // Nearest object that has something to offer. Reach is the object's own
    // interaction radius, so a large safe can be usable from further away than
    // a light switch without a special case here.
    UDerClueSmartObjectComponent* Best = nullptr;
    float BestDistance = TNumericLimits<float>::Max();
    for (UDerClueSmartObjectComponent* SmartObject : SmartObjects)
    {
        if (!SmartObject || !SmartObject->GetOwner())
        {
            continue;
        }
        if (SmartObject->GetAvailableActions(Thief).IsEmpty())
        {
            continue;
        }
        const float Distance = FVector::Dist2D(Thief->GetActorLocation(),
            SmartObject->GetOwner()->GetActorLocation());
        if (Distance < BestDistance)
        {
            BestDistance = Distance;
            Best = SmartObject;
        }
    }

    const bool bHasOffer = SmartObjectMenu->ShowFor(Best, Thief);
    SmartObjectMenu->SetVisibility(bHasOffer
        ? ESlateVisibility::SelfHitTestInvisible
        : ESlateVisibility::Collapsed);

    // A menu you cannot click is not a menu. Clicking UMG needs a cursor and an
    // input mode that lets Slate see the click at all; without both, the panel
    // draws and nothing happens when you press it.
    if (!PlayerController->IsA<ADebugCameraController>())
    {
        PlayerController->bShowMouseCursor = true;
    }

    CurrentActions.Reset();
    CurrentActionObject = Best;
    if (!bHasOffer || !Best)
    {
        return;
    }
    CurrentActions = Best->GetAvailableActions(Thief);

    // The same actions on number keys, spelled out on screen. The menu is the
    // intended way in, but the player must never be left guessing which key
    // opens a door -- especially while the menu itself is unproven.
    FString Hint = FString::Printf(TEXT("%s:"), *Best->GetDisplayName().ToString());
    for (int32 Index = 0; Index < CurrentActions.Num(); ++Index)
    {
        Hint += FString::Printf(TEXT("   [%d] %s"), Index + 1,
            *UDerClueSmartObjectComponent::GetActionLabel(CurrentActions[Index]).ToString());
    }
    if (GEngine)
    {
        GEngine->AddOnScreenDebugMessage(7716, 0.0f, FColor::Yellow, Hint);
    }
}

void ADerClueRuntimeDirector::TriggerAction(int32 Index)
{
    UDerClueSmartObjectComponent* Object = CurrentActionObject.Get();
    if (!Object || !Thief || !CurrentActions.IsValidIndex(Index))
    {
        return;
    }
    const EDerClueObjectAction Action = CurrentActions[Index];
    const bool bDone = Object->PerformAction(Thief, Action);
    if (GEngine)
    {
        GEngine->AddOnScreenDebugMessage(7717, 2.5f,
            bDone ? FColor::Green : FColor::Orange,
            FString::Printf(TEXT("%s -> %s"),
                *UDerClueSmartObjectComponent::GetActionLabel(Action).ToString(),
                bDone ? TEXT("done") : TEXT("not possible")));
    }
}

void ADerClueRuntimeDirector::TriggerAction1() { TriggerAction(0); }
void ADerClueRuntimeDirector::TriggerAction2() { TriggerAction(1); }
void ADerClueRuntimeDirector::TriggerAction3() { TriggerAction(2); }


bool ADerClueRuntimeDirector::PlayGuardAnim(UAnimSequence* Sequence, bool bLoop)
{
    if (!Guard || !Sequence)
    {
        return false;
    }
    if (USkeletalMeshComponent* Mesh = Guard->GetMesh())
    {
        if (Sequence->GetAdditiveAnimType() != AAT_None)
        {
            UE_LOG(LogTemp, Error,
                TEXT("DerClue animation: refusing additive clip '%s' as standalone guard animation."),
                *Sequence->GetPathName());
            return false;
        }
        const USkeleton* GuardSkeleton = Mesh->GetSkeletalMeshAsset()
            ? Mesh->GetSkeletalMeshAsset()->GetSkeleton()
            : nullptr;
        if (GuardSkeleton && !GuardSkeleton->IsCompatibleForEditor(Sequence->GetSkeleton()))
        {
            UE_LOG(LogTemp, Error,
                TEXT("DerClue animation: clip '%s' belongs to a different skeleton than guard mesh '%s'."),
                *Sequence->GetPathName(), *Mesh->GetSkeletalMeshAsset()->GetPathName());
            return false;
        }
        // PlayAnimation switches the component to single-node playback, which
        // is what lets one authored sequence run end to end without building a
        // montage or a second animation blueprint for a three-shot demo.
        Mesh->PlayAnimation(Sequence, bLoop);
        return true;
    }
    return false;
}

void ADerClueRuntimeDirector::PlayGuardActivityAnimation(EDerClueGuardActivity Activity)
{
    // Locomotion belongs to the character's Animation Blueprint. It already
    // blends idle/walk/run from real velocity and keeps feet synchronized.
    // Replacing it with a single animation asset breaks that state machine and
    // was the reason the robot kept walking during a 480 cm/s pursuit.
    RestoreCharacterAnimationBlueprint(Guard);
}

void ADerClueRuntimeDirector::RestoreCharacterAnimationBlueprint(ACharacter* Character) const
{
    if (Character)
    {
        if (USkeletalMeshComponent* Mesh = Character->GetMesh())
        {
            Mesh->SetAnimationMode(EAnimationMode::AnimationBlueprint);
        }
    }
}

void ADerClueRuntimeDirector::GuardDrawAndFire()
{
    if (!Guard)
    {
        return;
    }
    USkeletalMeshComponent* Mesh = Guard->GetMesh();
    if (!Mesh)
    {
        return;
    }

    // The weapon is created once and kept. Re-attaching it on every press
    // would make the pistol pop out of the hand for a frame each time.
    if (!GuardWeapon)
    {
        if (USkeletalMesh* WeaponAsset = GuardWeaponMesh.LoadSynchronous())
        {
            GuardWeapon = NewObject<USkeletalMeshComponent>(Guard, TEXT("GuardWeapon"));
            GuardWeapon->SetSkeletalMesh(WeaponAsset);
            GuardWeapon->SetCollisionEnabled(ECollisionEnabled::NoCollision);
            GuardWeapon->SetCanEverAffectNavigation(false);
            GuardWeapon->SetupAttachment(Mesh);
            GuardWeapon->RegisterComponent();
            GuardWeapon->AttachToComponent(Mesh,
                FAttachmentTransformRules::SnapToTargetNotIncludingScale, TEXT("hand_r"));
            GuardWeapon->SetRelativeLocation(FVector::ZeroVector);
            GuardWeapon->SetRelativeRotation(FRotator::ZeroRotator);
            GuardWeapon->SetUsingAbsoluteRotation(true);
            UpdateGuardWeaponTransform();
        }
    }
    if (GuardWeapon)
    {
        GuardWeapon->SetVisibility(true);
    }

    // Standing still for the draw: the guard walking mid-animation looks like
    // a bug rather than a decision.
    if (GuardController)
    {
        GuardController->StopMovement();
    }

    UAnimSequence* Equip = PistolEquipAnim.LoadSynchronous();
    PlayGuardAnim(Equip, false);
    if (GEngine)
    {
        GEngine->AddOnScreenDebugMessage(7720, 2.0f, FColor::Cyan, TEXT("Guard: drawing"));
    }
    const float EquipLength = Equip ? Equip->GetPlayLength() : 0.8f;
    GetWorldTimerManager().SetTimer(PistolStepTimer, this,
        &ADerClueRuntimeDirector::GuardAimStep, FMath::Max(0.1f, EquipLength), false);
}

void ADerClueRuntimeDirector::GuardAimStep()
{
    PlayGuardAnim(PistolAimAnim.LoadSynchronous(), true);
    if (GEngine)
    {
        GEngine->AddOnScreenDebugMessage(7720, 2.0f, FColor::Cyan, TEXT("Guard: aiming"));
    }
    GetWorldTimerManager().SetTimer(PistolStepTimer, this,
        &ADerClueRuntimeDirector::GuardFireStep, 1.2f, false);
}

void ADerClueRuntimeDirector::GuardFireStep()
{
    UAnimSequence* Fire = PistolFireAnim.LoadSynchronous();
    PlayGuardAnim(Fire, false);
    if (GEngine)
    {
        GEngine->AddOnScreenDebugMessage(7720, 2.0f, FColor::Orange, TEXT("Guard: FIRE"));
    }
    const float FireLength = Fire ? Fire->GetPlayLength() : 0.6f;
    GetWorldTimerManager().SetTimer(PistolStepTimer, this,
        &ADerClueRuntimeDirector::GuardFinishStep, FMath::Max(0.1f, FireLength) + 0.6f, false);
}

void ADerClueRuntimeDirector::GuardFinishStep()
{
    // Back to the animation blueprint, otherwise the guard is frozen in the
    // last pose of the fire sequence and never walks again.
    PlayGuardActivityAnimation(GuardBrain
        ? GuardBrain->GetActivity()
        : EDerClueGuardActivity::Patrol);
    if (GEngine)
    {
        GEngine->AddOnScreenDebugMessage(7720, 2.0f, FColor::Cyan, TEXT("Guard: back on patrol"));
    }
}


void ADerClueRuntimeDirector::EquipGuardWeapon()
{
    if (GuardWeapon || !Guard)
    {
        return;
    }
    USkeletalMeshComponent* Mesh = Guard->GetMesh();
    USkeletalMesh* WeaponAsset = GuardWeaponMesh.LoadSynchronous();
    if (!Mesh || !WeaponAsset)
    {
        return;
    }
    // The level now carries the weapon as an authored component so it is
    // visible while editing. Adopt that one; creating another here would put a
    // second gun on the guard the moment the mission starts.
    {
        TArray<USkeletalMeshComponent*> Existing;
        Guard->GetComponents(Existing);
        for (USkeletalMeshComponent* Candidate : Existing)
        {
            if (Candidate && Candidate != Mesh && Candidate->GetName().Contains(TEXT("GuardWeapon")))
            {
                GuardWeapon = Candidate;
                GuardWeapon->SetCollisionEnabled(ECollisionEnabled::NoCollision);
                GuardWeapon->SetCanEverAffectNavigation(false);
                GuardWeapon->SetUsingAbsoluteRotation(true);
                GuardWeapon->SetVisibility(true);
                UpdateGuardWeaponTransform();
                return;
            }
        }
    }
    // Carried from the start of the mission. A guard who produces a weapon out
    // of nowhere the moment he sees you reads as a cheat.
    GuardWeapon = NewObject<USkeletalMeshComponent>(Guard, TEXT("GuardWeapon"));
    GuardWeapon->SetSkeletalMesh(WeaponAsset);
    GuardWeapon->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    GuardWeapon->SetCanEverAffectNavigation(false);
    GuardWeapon->SetupAttachment(Mesh);
    GuardWeapon->RegisterComponent();
    GuardWeapon->AttachToComponent(Mesh,
        FAttachmentTransformRules::SnapToTargetNotIncludingScale, TEXT("hand_r"));
    GuardWeapon->SetRelativeLocation(FVector::ZeroVector);
    GuardWeapon->SetRelativeRotation(FRotator::ZeroRotator);
    GuardWeapon->SetUsingAbsoluteRotation(true);
    UpdateGuardWeaponTransform();
}

void ADerClueRuntimeDirector::BeginKillSequence()
{
    if (bKillSequenceStarted || !Guard || !Thief)
    {
        return;
    }
    bKillSequenceStarted = true;

    if (GuardController)
    {
        GuardController->StopMovement();
    }
    if (UCharacterMovementComponent* Movement = Guard->GetCharacterMovement())
    {
        Movement->bOrientRotationToMovement = false;
        Movement->StopMovementImmediately();
    }
    // Face the target before shooting; firing at a wall because the pursuit
    // ended off-angle looks broken.
    const FVector ToThief = Thief->GetActorLocation() - Guard->GetActorLocation();
    Guard->SetActorRotation(FRotationMatrix::MakeFromX(
        FVector(ToThief.X, ToThief.Y, 0.0f)).Rotator());

    // Straight to the shot: no draw, no aim hold. He is already carrying it.
    // Existing level instances can retain an older serialized property value,
    // so an invalid override falls back to the known compatible complete pose.
    UAnimSequence* Fire = PistolFireAnim.LoadSynchronous();
    bool bShotPlayed = PlayGuardAnim(Fire, false);
    if (!bShotPlayed)
    {
        Fire = LoadObject<UAnimSequence>(nullptr,
            TEXT("/Game/Characters/Mannequins/Anims/Pistol/MM_Pistol_DryFire.MM_Pistol_DryFire"));
        bShotPlayed = PlayGuardAnim(Fire, false);
    }
    if (!bShotPlayed)
    {
        UE_LOG(LogTemp, Error,
            TEXT("DerClue animation: kill sequence aborted because no compatible non-additive shot could play."));
        bKillSequenceStarted = false;
        RestoreCharacterAnimationBlueprint(Guard);
        return;
    }
    if (GEngine)
    {
        GEngine->AddOnScreenDebugMessage(7721, 3.0f, FColor::Red, TEXT("GUARD FIRES"));
    }
    const float ImpactDelay = Fire
        ? FMath::Clamp(Fire->GetPlayLength() * 0.55f, 0.08f, 0.22f)
        : 0.12f;
    GetWorldTimerManager().SetTimer(KillStepTimer, this,
        &ADerClueRuntimeDirector::KillDeathStep, ImpactDelay, false);
}

void ADerClueRuntimeDirector::KillDeathStep()
{
    if (!Thief)
    {
        return;
    }
    USkeletalMeshComponent* Mesh = Thief->GetMesh();
    if (Mesh && Mesh->GetPhysicsAsset())
    {
        // Chaos ragdoll is skeleton-independent and preserves the actual body
        // proportions. Playing a mannequin death on this actor looked like a
        // crouch because only part of the foreign pose mapped cleanly.
        if (UCapsuleComponent* Capsule = Thief->GetCapsuleComponent())
        {
            Capsule->SetCollisionEnabled(ECollisionEnabled::NoCollision);
        }
        Mesh->SetCollisionProfileName(TEXT("Ragdoll"));
        Mesh->SetAllBodiesSimulatePhysics(true);
        Mesh->SetSimulatePhysics(true);
        Mesh->WakeAllRigidBodies();
        FVector ImpulseDirection = Thief->GetActorLocation() - Guard->GetActorLocation();
        ImpulseDirection.Z = 0.0f;
        ImpulseDirection = ImpulseDirection.GetSafeNormal();
        Mesh->AddImpulse((ImpulseDirection * 19000.0f) + FVector(0.0f, 0.0f, 6500.0f),
            NAME_None, true);
        bThiefRagdollActive = true;
    }
    else if (UAnimSequence* Death = ThiefDeathAnim.LoadSynchronous())
    {
        // Fallback only for a character asset that has no Physics Asset.
        if (Mesh && Death->GetAdditiveAnimType() == AAT_None &&
            Mesh->GetSkeletalMeshAsset() && Mesh->GetSkeletalMeshAsset()->GetSkeleton() &&
            Mesh->GetSkeletalMeshAsset()->GetSkeleton()->IsCompatibleForEditor(Death->GetSkeleton()))
        {
            Mesh->PlayAnimation(Death, false);
        }
        else
        {
            UE_LOG(LogTemp, Error,
                TEXT("DerClue animation: thief has neither a usable Physics Asset nor a compatible death clip."));
        }
    }
    // Movement off, so the corpse does not slide away under its own input.
    if (UCharacterMovementComponent* Movement = Thief->GetCharacterMovement())
    {
        Movement->StopMovementImmediately();
        Movement->DisableMovement();
    }
    MissionState = EDerClueMissionState::Failed;
    SecurityState = EDerClueSecurityState::Lockdown;
    if (GEngine)
    {
        GEngine->AddOnScreenDebugMessage(7722, 6.0f, FColor::Red, TEXT("MISSION FAILED - shot on sight"));
    }
}
