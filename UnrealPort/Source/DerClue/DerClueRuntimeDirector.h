#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Navigation/PathFollowingComponent.h"
#include "DerClueRuntimeDirector.generated.h"

class AAIController;
class ACharacter;
class UDerClueSmartObjectComponent;
class USpotLightComponent;
class UPointLightComponent;
class AStaticMeshActor;
class ACameraActor;
class ASpotLight;

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
    float AlertMemorySeconds = 3.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Debug")
    bool bTechnicalOverlay = false;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Debug")
    bool bShowPatrolRoute = true;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Prototype")
    bool bKeepPrototypeDoorsOpen = true;

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

    TMap<TWeakObjectPtr<AActor>, FRotator> CameraBaseRotations;
    TArray<TObjectPtr<UDerClueSmartObjectComponent>> SmartObjects;
    TArray<FVector> PatrolRoutePolyline;
    FBox AuthoredLevelBounds = FBox(ForceInit);
    int32 CurrentPatrolIndex = 0;
    bool bInvestigating = false;
    bool bCamerasPowered = true;
    FVector InvestigationLocation = FVector::ZeroVector;
    float NextMoveRequestTime = 0.0f;
    float LastDetectionTime = -1000.0f;
    float NextInvestigationUpdateTime = 0.0f;
    float NextNoiseDeviceTime = 0.0f;
    bool bThiefInsideNoiseRadius = false;
    bool bPatrolRouteCacheReady = false;
    float NextPatrolRouteCacheAttempt = 0.0f;

    void DiscoverLevelActors();
    void ConfigureCharacter(ACharacter* Character) const;
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
    bool IsPatrolNodeOccupied(const AActor* Node) const;
    int32 FindNearestReachablePatrolNode() const;
    bool RequestMove(const FVector& Destination);
};
