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

    UFUNCTION(BlueprintCallable, Category="DerClue|Interaction")
    bool Interact(AActor* InstigatorActor);

    UFUNCTION(BlueprintCallable, Category="DerClue|Interaction")
    void SetOpen(bool bNewOpen);

    void UpdateDoor(float DeltaTime);

protected:
    virtual void BeginPlay() override;

private:
    FRotator ClosedRotation;
    FVector ClosedLocation = FVector::ZeroVector;
    FVector HingeLocation = FVector::ZeroVector;
    FVector DoorClosedAxis = FVector::ForwardVector;
    float DoorHalfLength = 0.0f;
    float DoorOpenAlpha = 0.0f;
    void ApplyDoorState();
};
