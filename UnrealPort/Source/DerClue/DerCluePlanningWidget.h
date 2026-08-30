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

    // Bound to widgets of the same name in the Widget Blueprint, so layout is
    // authored as an asset instead of being rebuilt in C++ on every construct.
    // A missing or mistyped binding fails the blueprint compile rather than
    // silently producing an empty panel at runtime.
    UPROPERTY(meta=(BindWidget))
    TObjectPtr<UButton> RecordButton;

    UPROPERTY(meta=(BindWidget))
    TObjectPtr<UButton> PlayButton;

    UPROPERTY(meta=(BindWidget))
    TObjectPtr<UTextBlock> RecordText;

    UPROPERTY(meta=(BindWidget))
    TObjectPtr<UTextBlock> StatusText;

    UFUNCTION()
    void HandleRecordClicked();

    UFUNCTION()
    void HandlePlayClicked();
};
