#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Navigation/PathFollowingComponent.h"
#include "Perception/AIPerceptionTypes.h"
#include "DerClueGuardBrainComponent.h"
#include "DerClueSmartObjectComponent.h"
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
class UStateTree;
class UStateTreeAIComponent;

UENUM(BlueprintType)
enum class EDerClueSecurityState : uint8
{
    Normal,
    Warning,
    Alarm,
    Lockdown
};

// Fixed viewpoints the owner can flip through at runtime. The top-down
// diorama stays the gameplay view; the rest exist so a human can actually
// look at the actors, which a locked overhead orthographic camera makes
// impossible.
UENUM(BlueprintType)
enum class EDerClueViewMode : uint8
{
    Diorama       UMETA(DisplayName="Top-down diorama"),
    OverShoulder  UMETA(DisplayName="Over the thief's shoulder"),
    ThiefFace     UMETA(DisplayName="Thief, front view"),
    GuardFace     UMETA(DisplayName="Guard, front view"),
    PawnCamera    UMETA(DisplayName="Pawn's own camera"),
    Free          UMETA(DisplayName="Free - director stops touching the view")
};

UENUM(BlueprintType)
enum class EDerClueMissionState : uint8
{
    InProgress,
    Success,
    Failed
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
    // 11 m, in the same league as the guard's own 10 m. The previous 5000
    // was 50 m on a level whose longest side is 30 m: one ceiling camera
    // covered the entire map, so the thief was under surveillance from the
    // spawn point in the far room and the guard was sent after him on the
    // first sweep. A camera should cover a room, not the level.
    float CameraVisionRange = 1100.0f;

    // Measure the camera's reach against the wall it actually faces instead of
    // trusting a hand-typed number. Off by default is not an option here: the
    // authored value cannot know where the camera was dropped.
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Vision")
    bool bCameraRangeReachesFacingWall = true;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Vision", meta=(ClampMin="1", ClampMax="179"))
    float CameraVisionAngle = 84.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Patrol")
    float PatrolAcceptanceRadius = 65.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Patrol")
    float OccupiedNodeRadius = 90.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Patrol")
    float RepathCooldown = 0.35f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Patrol")
    // An unhurried walking round. A patrol that hurries reads as a guard already
    // looking for someone, and it leaves the thief no room to time anything.
    // 150 exactly, because BS_Idle_Walk_Run has its samples on 0/150/300/450/600
    // and nothing in between. At 90 the graph blended 60% idle with 40% walk,
    // which reads as a standing robot twitching its heels rather than walking.
    // Anything slower than 150 degrades toward the idle pose for the same
    // reason -- a slower stroll needs a new sample in the blend space, not a
    // smaller number here.
    float GuardPatrolSpeed = 150.0f;

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

    // He runs the intercept, he does not stroll it. Patrol pace is a decision
    // the thief can time; a sighting is not.
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Security")
    float GuardPursuitSpeed = 480.0f;

    // Stops here and shoots instead of walking into the thief. Closing all the
    // way looked like a shove rather than an execution.
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Security")
    float GuardShootDistance = 280.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Security")
    TSoftObjectPtr<class UAnimSequence> ThiefDeathAnim;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Security")
    float InvestigationSearchDuration = 4.5f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Security")
    float InvestigationSearchHalfAngle = 65.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Security")
    float InvestigationSearchPeriod = 2.8f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Vision")
    // Right at the chest. The beam's pool starts where the cone meets the floor,
    // so what pushed it away from the guard was the shallow pitch below, not
    // this offset.
    float GuardFlashlightForwardOffset = 15.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Vision")
    float GuardFlashlightHeight = 105.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Vision")
    // 105cm high at -24 deg put the lit pool 2.4 m ahead of the guard, which
    // read as a beam that starts somewhere in front of him. At -38 deg it lands
    // about 1.3 m out, close enough to belong to the man holding it.
    float GuardFlashlightPitch = -38.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Debug")
    bool bTechnicalOverlay = false;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Debug")
    bool bShowPatrolRoute = true;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Prototype")
    bool bKeepPrototypeDoorsOpen = false;

    // The context menu is an asset so its look stays with a designer; only the
    // action rows are generated, from what each object reports it can do.
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Interaction")
    TSoftClassPtr<class UDerClueSmartObjectMenu> SmartObjectMenuClass;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Planning")
    float RecordedPointAcceptanceRadius = 75.0f;

    // The panel is a Widget Blueprint so its layout is authored as an asset.
    // Creating the C++ class directly would leave every BindWidget null, so the
    // class to instantiate is a property rather than a hardcoded StaticClass.
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Planning")
    TSoftClassPtr<UDerCluePlanningWidget> PlanningWidgetClass;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|AI")
    TSoftObjectPtr<UStateTree> GuardStateTreeAsset;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Mission")
    float BaseReturnRadius = 140.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Prototype")
    float NoiseDeviceTriggerRadius = 150.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Prototype")
    float NoiseDeviceCooldown = 10.0f;

    // RVO group ids. Kept named rather than inline so the guard's "avoid the
    // thief" rule cannot silently drift apart from the thief's own group.
    static constexpr uint8 ThiefAvoidanceGroup = 0;
    static constexpr uint8 GuardAvoidanceGroup = 1;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera")
    bool bUseFixedDioramaCamera = true;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera")
    float FixedDioramaCameraHeight = 2200.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera")
    float FixedDioramaCameraDistance = 950.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera", meta=(ClampMin="1.0"))
    float FixedDioramaCameraMargin = 1.12f;

    // Distance and height of the inspection camera in the shoulder/face views.
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera")
    float ShoulderCameraDistance = 320.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera")
    float ShoulderCameraHeight = 165.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera")
    float ShoulderCameraSideOffset = 65.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera")
    float FaceCameraDistance = 230.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera")
    float FaceCameraHeight = 155.0f;

    // Orbit controls for the diorama view. Right-drag rotates, wheel zooms;
    // the left button stays free so inspecting never competes with
    // click-to-move.
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera")
    float DioramaOrbitSensitivity = 2.5f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera")
    float DioramaOrbitMinPitch = -85.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera")
    float DioramaOrbitMaxPitch = -12.0f;

    // Any CameraActor in the level tagged DerClue.ViewCamera joins the cycle,
    // so extra viewpoints can be authored in the editor without code changes.
    UPROPERTY(BlueprintReadOnly, Category="DerClue|Camera")
    TArray<TObjectPtr<AActor>> ExtraViewCameras;

    UPROPERTY(BlueprintReadOnly, Category="DerClue|Camera")
    EDerClueViewMode ViewMode = EDerClueViewMode::Diorama;

    // Which view the mission opens on. Index 3 is the guard's front view, so
    // his animations are visible the moment Play is pressed.
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Camera")
    int32 StartingViewIndex = 0;

    // Bound to the C key; also callable from Blueprint or the console.
    // Bound to G: draw, aim, fire. The pistol set lives on SK_Mannequin, so it
    // plays on the guard through the same Compatible Skeletons path that drives
    // his walk -- no retargeting for the weapon animations either.
    UFUNCTION(BlueprintCallable, Category="DerClue|Guard")
    void GuardDrawAndFire();

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Guard")
    TSoftObjectPtr<class USkeletalMesh> GuardWeaponMesh;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Guard")
    TSoftObjectPtr<class UAnimSequence> PistolEquipAnim;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Guard")
    TSoftObjectPtr<class UAnimSequence> PistolAimAnim;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Guard")
    TSoftObjectPtr<class UAnimSequence> PistolFireAnim;

    // Native, non-additive rifle locomotion from the same SciFiSoldier
    // skeleton as BP_GrantGuard. These are deliberately separate from the
    // generic mannequin set: an additive recoil clip cannot be played as a
    // complete pose, and a foreign skeleton must not silently become the
    // guard's production locomotion source.
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Guard")
    TSoftObjectPtr<class UAnimSequence> GuardWalkWeaponAnim;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Guard")
    TSoftObjectPtr<class UAnimSequence> GuardJogWeaponAnim;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Guard")
    TSoftObjectPtr<class UAnimSequence> GuardRunWeaponAnim;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Guard")
    TSoftObjectPtr<class UAnimSequence> GuardIdleWeaponAnim;

    // Where the weapon sits in the hand. The robot ships no sockets, so it is
    // attached to hand_r directly and nudged into the grip by these.
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Guard")
    FVector WeaponGripOffset = FVector(-3.0f, 5.0f, -2.0f);

    // --- Arm pose ---------------------------------------------------------
    // The arm is posed directly on the bones instead of through an animation.
    // Every flashlight animation in the project sits on a first-person arms
    // skeleton that has no legs, so playing one whole would freeze the guard's
    // lower body in its reference pose. Overriding three bones leaves the body
    // animation untouched and costs no AnimBP work.
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Guard|Arm")
    bool bOverrideGuardArmPose = false;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Guard|Arm")
    FRotator GuardUpperArmPose = FRotator(-52.0f, 0.0f, 0.0f);

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Guard|Arm")
    FRotator GuardLowerArmPose = FRotator(-38.0f, 0.0f, 0.0f);

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Guard|Arm")
    FRotator GuardHandPose = FRotator(0.0f, 0.0f, 0.0f);

    // How far the arm drifts, in degrees, and how fast. Two sine waves of
    // different periods keep it from reading as a metronome.
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Guard|Arm")
    float GuardArmSwayYaw = 6.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Guard|Arm")
    float GuardArmSwayPitch = 3.5f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Guard|Arm")
    float GuardArmSwaySpeed = 1.15f;

    // How much of the guard's own turning the arm follows. The arm lags the
    // body, so a turn throws the beam wide before it settles back.
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Guard|Arm")
    float GuardArmFollowTurn = 0.45f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Guard")
    // Correction from the hand bone's axes to the weapon mesh's. This value
    // was dialled by eye for the old first-person gun (barrel on local +Y).
    // The mesh is now SK_Revolver, so expect to re-dial it in the level.
    FRotator WeaponGripRotation = FRotator(0.0f, -90.0f, 0.0f);

    // The menu's rows, also reachable from the number keys.
    UFUNCTION(BlueprintCallable, Category="DerClue|Interaction")
    void TriggerAction(int32 Index);

    UFUNCTION() void TriggerAction1();
    UFUNCTION() void TriggerAction2();
    UFUNCTION() void TriggerAction3();

    UFUNCTION(BlueprintCallable, Category="DerClue|Camera")
    void CycleViewMode();

    UFUNCTION(BlueprintCallable, Category="DerClue|Camera")
    void SetViewIndex(int32 NewIndex);

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
    TObjectPtr<UDerClueGuardBrainComponent> GuardBrain;

    UPROPERTY()
    TObjectPtr<UStateTreeAIComponent> GuardStateTreeComponent;

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

    // One reusable perspective camera, re-aimed every frame for whichever
    // inspection view is active. Spawning one per view would leave idle actors
    // ticking in the level for no reason.
    UPROPERTY()
    TObjectPtr<ACameraActor> InspectionCamera;

    UPROPERTY()
    TObjectPtr<class UDerClueSmartObjectMenu> SmartObjectMenu;

    UPROPERTY()
    TObjectPtr<class USkeletalMeshComponent> GuardWeapon;

    FTransform ThiefMeshStartRelativeTransform = FTransform::Identity;
    FName ThiefMeshStartCollisionProfile;
    bool bThiefRagdollActive = false;

    FTimerHandle PistolStepTimer;
    FTimerHandle KillStepTimer;
    bool bKillSequenceStarted = false;

    UPROPERTY()
    TWeakObjectPtr<UDerClueSmartObjectComponent> CurrentActionObject;

    UPROPERTY()
    TArray<EDerClueObjectAction> CurrentActions;

    int32 ViewIndex = 0;

    // Applying the view target only when the choice changes, instead of every
    // frame, is what lets F8 eject and "toggledebugcamera" survive: the
    // director no longer yanks the view back the instant something else
    // takes it.
    TWeakObjectPtr<AActor> LastAppliedViewTarget;

    FVector DioramaCentre = FVector::ZeroVector;
    FVector DioramaDefaultCentre = FVector::ZeroVector;
    FVector DioramaBaseOffset = FVector::ZeroVector;
    float DioramaBaseOrthoWidth = 0.0f;
    float DioramaOrbitYaw = 0.0f;
    float DioramaOrbitPitch = 0.0f;
    float DioramaDefaultYaw = 0.0f;
    float DioramaDefaultPitch = 0.0f;
    float DioramaOrbitRadius = 950.0f;
    float DioramaCameraHeight = 2200.0f;
    float DioramaDefaultCameraHeight = 2200.0f;
    float DioramaZoom = 1.0f;
    bool bDioramaOrbitDragging = false;

    // Wheel zoom for the close-up views. Without it the only adjustable camera
    // was the top-down one, so there was no way to get near the guard at all.
    float InspectionZoom = 1.0f;
    bool bDioramaOrbitReady = false;

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
    bool bCamerasPowered = true;
    bool bCameraHadContact = false;
    // Latched only by the guard's own sight. Once he has visually acquired the
    // thief, a one-frame perception loss while turning at close range must not
    // cancel the arrest/shot.
    bool bGuardHasAcquiredThief = false;
    // Driven by AIPerception sight stimuli rather than polled each tick, so
    // gaining and losing the thief is decided by the same sense that reports
    // noise instead of by a parallel hand-rolled cone test.
    bool bConfirmedIntrusion = false;
    float NextNoiseDeviceTime = 0.0f;
    bool bThiefInsideNoiseRadius = false;
    bool bNoiseDeviceBaselineInitialized = false;
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
    void ConfigureGuardBrain();
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
    void ConfigureViewCameras();
    void UpdateViewCamera(float DeltaSeconds);
    void AimInspectionCamera(const AActor* Subject, bool bFromFront);
    void UpdateDioramaOrbit(APlayerController* PlayerController);
    void ResetDioramaView();
    void RaiseDioramaCamera();
    void LowerDioramaCamera();
    void UpdateGuardWeaponTransform();

    // Advances the sway and turn-lag values. The bones themselves are written
    // later, from the mesh's own finalize callback.
    void UpdateGuardArmPose(float DeltaSeconds);

    // Hooks/unhooks the finalize callback on the guard's mesh.
    void BindGuardArmPose();

    // Rewrites the arm bones in the finalized component-space pose.
    void ApplyGuardArmPoseToBones();

    // Running phase for the sway, and the guard's yaw last frame so the arm
    // can lag behind a turn instead of snapping with it.
    float GuardArmSwayPhase = 0.0f;
    float GuardArmLastYaw = 0.0f;
    float GuardArmTurnLag = 0.0f;
    // Resolved once per frame in UpdateGuardArmPose, consumed by the callback.
    FRotator GuardArmResolvedUpperArm = FRotator::ZeroRotator;
    FDelegateHandle GuardArmPoseHandle;
    TWeakObjectPtr<class USkeletalMeshComponent> GuardArmBoundMesh;
    void UpdateSmartObjectMenu();
    bool PlayGuardAnim(class UAnimSequence* Sequence, bool bLoop);
    void PlayGuardActivityAnimation(EDerClueGuardActivity Activity);
    void RestoreCharacterAnimationBlueprint(ACharacter* Character) const;
    void GuardAimStep();
    void GuardFireStep();
    void GuardFinishStep();
    void BeginKillSequence();
    void KillDeathStep();
    void EquipGuardWeapon();
    void EnsureCoreActors();
    void RefreshPlayableThief();
    void UpdateCameras(float DeltaSeconds);
    void UpdateVision();
    void UpdateTechnicalOverlay();
    void RebuildPatrolRouteCache();
    void PositionPatrolNodesAcrossLevel();
    void CacheAuthoredLevelBounds();
    void UpdateMissionState();
    void DrawVisionFootprint(const AActor* Source, float Range, float FullAngleDegrees, const FColor& Color) const;
    void UpdateSmartObjects();

    UFUNCTION()
    void HandleGuardPerception(AActor* Actor, FAIStimulus Stimulus);

    UFUNCTION()
    void HandleGuardActivityChanged(EDerClueGuardActivity Activity);
};
