#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Navigation/PathFollowingComponent.h"
#include "Perception/AIPerceptionTypes.h"
#include "DerClueRuntimeDirector.generated.h"

class AAIController;
class ACharacter;
class UDerClueSmartObjectComponent;
class USpotLightComponent;
class UPointLightComponent;
class AStaticMeshActor;
class ACameraActor;
class ASpotLight;
class UAIPerceptionComponent;
class UAISenseConfig_Hearing;
class UAISenseConfig_Sight;
class UDerCluePlanningWidget;

UENUM(BlueprintType)
enum class EDerClueSecurityState : uint8
{
    Normal,
    Warning,
    Alarm,
    Lockdown
};

UENUM(BlueprintType)
enum class EDerClueMissionState : uint8
{
    InProgress,
    Success,
    Failed
};

enum class EDerClueGuardActivity : uint8
{
    Patrol,
    Investigate,
    Search,
    Pursue,
    IntruderSweep
};

enum class EDerClueRouteMode : uint8
{
    Free,
    Recording,
    Ready,
    Playing
};

struct FDerClueSmartObjectSnapshot
{
    TWeakObjectPtr<UDerClueSmartObjectComponent> Object;
    bool bLocked = false;
    bool bOpen = false;
    bool bPowered = true;
    bool bCollected = false;
};

UCLASS(BlueprintType, Blueprintable)
class DERCLUE_API ADerClueRuntimeDirector : public AActor
{
    GENERATED_BODY()

public:
    ADerClueRuntimeDirector();
    virtual void Tick(float DeltaSeconds) override;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Patrol")
    FName GuardTag = TEXT("DerClue.Guard");

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Patrol")
    FName PatrolNodeTag = TEXT("DerClue.PatrolNode");

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Actors")
    FName ThiefTag = TEXT("DerClue.Thief");

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Vision")
    FName SecurityCameraTag = TEXT("DerClue.SecurityCamera");

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Vision")
    FName CameraVisualTag = TEXT("DerClue.CameraVisual");

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Security")
    FName AlarmLightTag = TEXT("DerClue.AlarmLight");

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Vision")
    float GuardVisionRange = 1000.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Vision", meta=(ClampMin="1", ClampMax="179"))
    float GuardVisionAngle = 40.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Vision")
    float CameraVisionRange = 5000.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Vision", meta=(ClampMin="1", ClampMax="179"))
    float CameraVisionAngle = 84.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Patrol")
    float PatrolAcceptanceRadius = 65.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Patrol")
    float OccupiedNodeRadius = 90.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Patrol")
    float RepathCooldown = 0.35f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Patrol")
    float GuardPatrolSpeed = 125.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Patrol")
    float GuardInvestigationSpeed = 190.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Patrol")
    float GuardIntruderSweepSpeed = 230.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Patrol")
    float PatrolCornerInset = 180.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Actors")
    float ThiefMoveSpeed = 260.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera")
    float CameraSweepHalfAngle = 42.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera")
    float CameraSweepPeriod = 14.0f;

    UPROPERTY(BlueprintReadOnly, Category="DerClue|Security")
    EDerClueSecurityState SecurityState = EDerClueSecurityState::Normal;

    UPROPERTY(BlueprintReadOnly, Category="DerClue|Mission")
    EDerClueMissionState MissionState = EDerClueMissionState::InProgress;

    UPROPERTY(BlueprintReadOnly, Category="DerClue|Mission")
    bool bHasLoot = false;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Mission")
    float CaptureDistance = 115.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Security")
    float InvestigationSearchDuration = 4.5f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Security")
    float InvestigationSearchHalfAngle = 65.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Security")
    float InvestigationSearchPeriod = 2.8f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Vision")
    float GuardFlashlightForwardOffset = 30.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Vision")
    float GuardFlashlightHeight = 105.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Vision")
    float GuardFlashlightPitch = -24.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Debug")
    bool bTechnicalOverlay = false;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Debug")
    bool bShowPatrolRoute = true;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Prototype")
    bool bKeepPrototypeDoorsOpen = false;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Planning")
    float RecordedPointAcceptanceRadius = 75.0f;

    // The panel is a Widget Blueprint so its layout is authored as an asset.
    // Creating the C++ class directly would leave every BindWidget null, so the
    // class to instantiate is a property rather than a hardcoded StaticClass.
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Planning")
    TSoftClassPtr<UDerCluePlanningWidget> PlanningWidgetClass;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Mission")
    float BaseReturnRadius = 140.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Prototype")
    float NoiseDeviceTriggerRadius = 150.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Prototype")
    float NoiseDeviceCooldown = 10.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera")
    bool bUseFixedDioramaCamera = true;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera")
    float FixedDioramaCameraHeight = 2200.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera")
    float FixedDioramaCameraDistance = 950.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera", meta=(ClampMin="1.0"))
    float FixedDioramaCameraMargin = 1.12f;

    UFUNCTION(BlueprintCallable, Category="DerClue|Patrol")
    void InvestigateLocation(FVector WorldLocation);

    UFUNCTION(BlueprintCallable, Category="DerClue|Patrol")
    void ReturnToNearestPatrolNode();

    UFUNCTION(BlueprintCallable, Category="DerClue|Planning")
    void ToggleRouteRecording();

    UFUNCTION(BlueprintCallable, Category="DerClue|Planning")
    void PlayRecordedRoute();

    UFUNCTION(BlueprintCallable, Category="DerClue|Interaction")
    bool Interact(ACharacter* Character, AActor* Target);

    UFUNCTION(BlueprintPure, Category="DerClue|Vision")
    bool CanSeeTarget(const AActor* Source, const AActor* Target, float Range, float FullAngleDegrees) const;

protected:
    virtual void BeginPlay() override;

private:
    UPROPERTY()
    TObjectPtr<ACharacter> Guard;

    UPROPERTY()
    TObjectPtr<ACharacter> Thief;

    UPROPERTY()
    TObjectPtr<AAIController> GuardController;

    UPROPERTY()
    TArray<TObjectPtr<AActor>> PatrolNodes;

    UPROPERTY()
    TArray<TObjectPtr<AActor>> SecurityCameras;

    UPROPERTY()
    TArray<TObjectPtr<AActor>> CameraVisuals;

    UPROPERTY()
    TArray<TObjectPtr<UPointLightComponent>> AlarmLights;

    UPROPERTY()
    TObjectPtr<AStaticMeshActor> NoiseDevice;

    UPROPERTY()
    TObjectPtr<AStaticMeshActor> CameraOcclusionBox;

    UPROPERTY()
    TObjectPtr<ACameraActor> DioramaCamera;

    UPROPERTY()
    TObjectPtr<ASpotLight> GuardFlashlight;

    UPROPERTY()
    TObjectPtr<UAIPerceptionComponent> GuardPerception;

    UPROPERTY()
    TObjectPtr<UAISenseConfig_Hearing> GuardHearingConfig;

    UPROPERTY()
    TObjectPtr<UAISenseConfig_Sight> GuardSightConfig;

    UPROPERTY()
    TObjectPtr<UDerCluePlanningWidget> PlanningWidget;

    TMap<TWeakObjectPtr<AActor>, FRotator> CameraBaseRotations;
    TArray<TObjectPtr<UDerClueSmartObjectComponent>> SmartObjects;
    TArray<FVector> PatrolRoutePolyline;
    FBox AuthoredLevelBounds = FBox(ForceInit);
    int32 CurrentPatrolIndex = 0;
    EDerClueGuardActivity GuardActivity = EDerClueGuardActivity::Patrol;
    bool bCamerasPowered = true;
    bool bCameraHadContact = false;
    // Driven by AIPerception sight stimuli rather than polled each tick, so
    // gaining and losing the thief is decided by the same sense that reports
    // noise instead of by a parallel hand-rolled cone test.
    bool bGuardHasVisualOnThief = false;
    bool bConfirmedIntrusion = false;
    FVector InvestigationLocation = FVector::ZeroVector;
    float NextMoveRequestTime = 0.0f;
    float SearchStartedTime = 0.0f;
    float SearchEndTime = 0.0f;
    float SearchBaseYaw = 0.0f;
    float NextNoiseDeviceTime = 0.0f;
    bool bThiefInsideNoiseRadius = false;
    bool bPatrolRouteCacheReady = false;
    float NextPatrolRouteCacheAttempt = 0.0f;
    EDerClueRouteMode RouteMode = EDerClueRouteMode::Free;
    TArray<FVector> RecordedDestinations;
    TArray<FDerClueSmartObjectSnapshot> MissionObjectSnapshot;
    FTransform ThiefStartTransform;
    FTransform GuardStartTransform;
    FVector BaseLocation = FVector::ZeroVector;
    int32 PlaybackDestinationIndex = INDEX_NONE;
    bool bPlaybackMoveIssued = false;
    bool bSuppressNextRecordedClick = false;
    bool bObjectiveNotificationShown = false;
    float SimulationEpochSeconds = 0.0f;

    void DiscoverLevelActors();
    void ConfigureCharacter(ACharacter* Character) const;
    void ConfigureGuardPerception();
    void CreatePlanningWidget();
    void CaptureMissionSnapshot();
    void RestoreMissionSnapshot();
    void UpdateRoutePlanning();
    void RefreshPlanningWidget();
    void ConfigureVisionLights();
    void ConfigureWorldAndSmartObjects();
    void CreatePrototypeTestObjects();
    void UpdateNoiseDevice();
    void ConfigureDioramaCamera();
    void EnsureCoreActors();
    void RefreshPlayableThief();
    void UpdatePatrol();
    void UpdateCameras(float DeltaSeconds);
    void UpdateVision();
    void UpdateTechnicalOverlay();
    void RebuildPatrolRouteCache();
    void PositionPatrolNodesAcrossLevel();
    void CacheAuthoredLevelBounds();
    void UpdateMissionState();
    void DrawVisionFootprint(const AActor* Source, float Range, float FullAngleDegrees, const FColor& Color) const;
    void UpdateSmartObjects();
    void BeginIntruderSweep();
    bool IsPatrolNodeOccupied(const AActor* Node) const;
    int32 FindNearestReachablePatrolNode() const;
    bool RequestMove(const FVector& Destination);

    UFUNCTION()
    void HandleGuardPerception(AActor* Actor, FAIStimulus Stimulus);
};
