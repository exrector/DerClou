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
#include "Camera/CameraComponent.h"

ADerClueRuntimeDirector::ADerClueRuntimeDirector()
{
    PrimaryActorTick.bCanEverTick = true;
    PrimaryActorTick.TickInterval = 1.0f / 30.0f;
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
    CreatePrototypeTestObjects();
    ConfigureDioramaCamera();
    ReturnToNearestPatrolNode();
}

void ADerClueRuntimeDirector::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);
    RefreshPlayableThief();
    if (bUseFixedDioramaCamera && DioramaCamera)
    {
        if (APlayerController* PlayerController = GetWorld()->GetFirstPlayerController())
        {
            if (PlayerController->GetViewTarget() != DioramaCamera)
            {
                PlayerController->SetViewTarget(DioramaCamera);
            }
        }
    }
    UpdateCameras(DeltaSeconds);
    UpdateVision();
    UpdateSmartObjects();
    UpdateNoiseDevice();
    UpdatePatrol();
    UpdateMissionState();
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

void ADerClueRuntimeDirector::CreatePrototypeTestObjects()
{
    UStaticMesh* CubeMesh = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
    if (!CubeMesh || !GetWorld())
    {
        return;
    }

    FVector Centre = FVector::ZeroVector;
    for (AActor* Node : PatrolNodes)
    {
        Centre += Node ? Node->GetActorLocation() : FVector::ZeroVector;
    }
    if (!PatrolNodes.IsEmpty())
    {
        Centre /= static_cast<float>(PatrolNodes.Num());
    }
    Centre.Z = 18.0f;
    NoiseDevice = GetWorld()->SpawnActor<AStaticMeshActor>(Centre + FVector(0.0f, -180.0f, 0.0f), FRotator::ZeroRotator);
    if (NoiseDevice)
    {
        NoiseDevice->SetActorScale3D(FVector(0.34f, 0.24f, 0.18f));
        NoiseDevice->GetStaticMeshComponent()->SetStaticMesh(CubeMesh);
        NoiseDevice->GetStaticMeshComponent()->SetCollisionEnabled(ECollisionEnabled::NoCollision);
        NoiseDevice->GetStaticMeshComponent()->SetCanEverAffectNavigation(false);
        NoiseDevice->Tags.AddUnique(TEXT("DerClue.NoiseDevice"));
    }

    if (!SecurityCameras.IsEmpty())
    {
        AActor* Camera = SecurityCameras[0];
        FVector Forward = Camera->GetActorForwardVector();
        Forward.Z = 0.0f;
        Forward.Normalize();
        FVector BoxLocation = Camera->GetActorLocation() + Forward * 650.0f;
        BoxLocation.Z = 50.0f;
        CameraOcclusionBox = GetWorld()->SpawnActor<AStaticMeshActor>(BoxLocation, FRotator::ZeroRotator);
        if (CameraOcclusionBox)
        {
            CameraOcclusionBox->SetActorScale3D(FVector(0.65f));
            UStaticMeshComponent* Mesh = CameraOcclusionBox->GetStaticMeshComponent();
            Mesh->SetStaticMesh(CubeMesh);
            Mesh->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
            Mesh->SetCollisionResponseToChannel(ECC_Visibility, ECR_Block);
            Mesh->SetCollisionResponseToChannel(ECC_Pawn, ECR_Block);
            Mesh->SetCanEverAffectNavigation(true);
            CameraOcclusionBox->Tags.AddUnique(TEXT("DerClue.CameraOcclusionTest"));
        }

        // Placed level geometry is authoritative. Vision tests may trace against
        // furniture, but must never hide, disable, move, or otherwise rewrite it.
    }
}

void ADerClueRuntimeDirector::UpdateNoiseDevice()
{
    if (!NoiseDevice || !Thief || !Guard)
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
        LastDetectionTime = Now;
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
        if (!Actor || Actor->ActorHasTag(PatrolNodeTag))
        {
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
        // level. Bind the nearest non-camera spotlight once, preserving its
        // carefully authored world offset and downward pitch.
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
            GuardFlashlight->AttachToActor(Guard, FAttachmentTransformRules::KeepWorldTransform);
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

        if (SmartObject->Kind == EDerClueSmartObjectKind::Door && bKeepPrototypeDoorsOpen)
        {
            SmartObject->SetOpen(true);
        }
        else if (SmartObject->Kind == EDerClueSmartObjectKind::Door && Nearest <= SmartObject->InteractionRadius)
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
    bInvestigating = true;
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
    bInvestigating = false;
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

void ADerClueRuntimeDirector::UpdateCameras(float DeltaSeconds)
{
    // A readable stealth window is part of the level contract: the thief must
    // have enough time to move between the authored cover objects.
    const float Period = FMath::Max(14.0f, CameraSweepPeriod);
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
