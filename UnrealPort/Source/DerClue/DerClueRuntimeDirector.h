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
class UNavModifierComponent;

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
    float GuardVisionRange = 1600.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Vision", meta=(ClampMin="1", ClampMax="179"))
    float GuardVisionAngle = 40.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Vision")
    float CameraVisionRange = 2200.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Vision", meta=(ClampMin="1", ClampMax="179"))
    float CameraVisionAngle = 84.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Patrol")
    float PatrolAcceptanceRadius = 65.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Patrol")
    float OccupiedNodeRadius = 90.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Patrol")
    float RepathCooldown = 0.35f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Avoidance")
    float StationaryObstacleActivationDelay = 0.25f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Avoidance")
    float StationaryObstacleInfluenceRadius = 700.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera")
    float CameraSweepHalfAngle = 42.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera")
    float CameraSweepPeriod = 6.0f;

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
    bool bTechnicalOverlay = true;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Debug")
    bool bShowPatrolRoute = true;

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
    TObjectPtr<UNavModifierComponent> ThiefNavObstacle;

    TMap<TWeakObjectPtr<AActor>, FRotator> CameraBaseRotations;
    TArray<TObjectPtr<UDerClueSmartObjectComponent>> SmartObjects;
    int32 CurrentPatrolIndex = 0;
    bool bInvestigating = false;
    bool bCamerasPowered = true;
    FVector InvestigationLocation = FVector::ZeroVector;
    float NextMoveRequestTime = 0.0f;
    float LastDetectionTime = -1000.0f;
    float NextInvestigationUpdateTime = 0.0f;
    float ThiefStationarySince = -1.0f;
    bool bThiefNavObstacleEnabled = false;

    void DiscoverLevelActors();
    void ConfigureCharacter(ACharacter* Character) const;
    void ConfigureVisionLights();
    void ConfigureWorldAndSmartObjects();
    void UpdatePatrol();
    void UpdateCameras(float DeltaSeconds);
    void UpdateVision();
    void UpdateAlarmPresentation();
    void UpdateDynamicActorAvoidance();
    void UpdateTechnicalOverlay();
    void UpdateMissionState();
    void DrawVisionFootprint(const AActor* Source, float Range, float FullAngleDegrees, const FColor& Color) const;
    void UpdateSmartObjects();
    bool IsPatrolNodeOccupied(const AActor* Node) const;
    int32 FindNearestReachablePatrolNode() const;
    bool RequestMove(const FVector& Destination);
};
