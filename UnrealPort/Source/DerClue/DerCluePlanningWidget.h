#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "DerCluePlanningWidget.generated.h"

class UButton;
class UTextBlock;
class ADerClueRuntimeDirector;

UCLASS()
class DERCLUE_API UDerCluePlanningWidget : public UUserWidget
{
    GENERATED_BODY()

public:
    void SetDirector(ADerClueRuntimeDirector* InDirector);
    void Refresh(const FText& RecordLabel, const FText& Status, bool bCanPlay);

protected:
    virtual void NativeConstruct() override;

private:
    UPROPERTY()
    TObjectPtr<ADerClueRuntimeDirector> Director;

    UPROPERTY()
    TObjectPtr<UButton> RecordButton;

    UPROPERTY()
    TObjectPtr<UButton> PlayButton;

    UPROPERTY()
    TObjectPtr<UTextBlock> RecordText;

    UPROPERTY()
    TObjectPtr<UTextBlock> StatusText;

    UFUNCTION()
    void HandleRecordClicked();

    UFUNCTION()
    void HandlePlayClicked();
};
