#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "DerClueSmartObjectComponent.generated.h"

UENUM(BlueprintType)
enum class EDerClueSmartObjectKind : uint8
{
    Furniture,
    Door,
    SecurityPanel,
    Safe,
    Loot,
    Extraction
};

UCLASS(ClassGroup=(DerClue), BlueprintType, Blueprintable, meta=(BlueprintSpawnableComponent))
class DERCLUE_API UDerClueSmartObjectComponent : public UActorComponent
{
    GENERATED_BODY()

public:
    UDerClueSmartObjectComponent();

    virtual void TickComponent(float DeltaTime, ELevelTick TickType,
        FActorComponentTickFunction* ThisTickFunction) override;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Identity")
    FName StableId;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Interaction")
    EDerClueSmartObjectKind Kind = EDerClueSmartObjectKind::Furniture;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Interaction")
    float InteractionRadius = 160.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|State")
    bool bLocked = false;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|State")
    bool bOpen = false;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|State")
    bool bPowered = true;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|State")
    bool bCollected = false;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Door")
    float OpenYaw = 90.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Door", meta=(ClampMin="0.05"))
    float DoorTransitionSeconds = 0.35f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Noise")
    float NoiseLoudness = 1.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="DerClue|Noise")
    float NoiseMaxRange = 1400.0f;

    UFUNCTION(BlueprintCallable, Category="DerClue|Interaction")
    bool Interact(AActor* InstigatorActor);

    UFUNCTION(BlueprintCallable, Category="DerClue|Interaction")
    void SetOpen(bool bNewOpen);

    UFUNCTION(BlueprintCallable, Category="DerClue|Noise")
    void EmitNoise(AActor* InstigatorActor);

    void RestoreState(bool bNewLocked, bool bNewOpen, bool bNewPowered, bool bNewCollected);

    void UpdateDoor(float DeltaTime);

protected:
    virtual void BeginPlay() override;

private:
    // A locked door is the only door that may carve the navmesh. An unlocked
    // one -- even while shut -- must leave the doorway navigable, otherwise no
    // cross-room path can ever be planned and the actor walks into the wall
    // instead of walking up to the door and opening it.
    UPROPERTY()
    TObjectPtr<class UNavModifierComponent> NavModifier;

    FRotator ClosedRotation;
    FVector ClosedLocation = FVector::ZeroVector;
    // Pivot-to-centre vector captured while shut. These prototype meshes are
    // unit cubes whose pivot sits on a corner, so GetActorLocation() is NOT the
    // slab centre and the hinge cannot be derived from it directly.
    FVector ClosedCenterOffset = FVector::ZeroVector;
    FVector HingeLocation = FVector::ZeroVector;
    FVector DoorClosedAxis = FVector::ForwardVector;
    float DoorHalfLength = 0.0f;
    float DoorOpenAlpha = 0.0f;
    void ApplyDoorState();
    void ApplyDoorNavigation();
};
