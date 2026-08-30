#include "DerCluePlanningWidget.h"

#include "DerClueRuntimeDirector.h"
#include "Components/Button.h"
#include "Components/TextBlock.h"

void UDerCluePlanningWidget::NativeConstruct()
{
    Super::NativeConstruct();

    // The widget tree now comes from the Widget Blueprint; only behaviour is
    // wired here. Bindings are guaranteed by BindWidget, so a null here would
    // mean the asset failed to compile rather than a layout mistake.
    if (RecordButton)
    {
        RecordButton->OnClicked.RemoveDynamic(this, &UDerCluePlanningWidget::HandleRecordClicked);
        RecordButton->OnClicked.AddDynamic(this, &UDerCluePlanningWidget::HandleRecordClicked);
    }
    if (PlayButton)
    {
        PlayButton->OnClicked.RemoveDynamic(this, &UDerCluePlanningWidget::HandlePlayClicked);
        PlayButton->OnClicked.AddDynamic(this, &UDerCluePlanningWidget::HandlePlayClicked);
    }
}

void UDerCluePlanningWidget::SetDirector(ADerClueRuntimeDirector* InDirector)
{
    Director = InDirector;
}

void UDerCluePlanningWidget::Refresh(const FText& RecordLabel, const FText& Status, bool bCanPlay)
{
    if (RecordText)
    {
        RecordText->SetText(RecordLabel);
    }
    if (StatusText)
    {
        StatusText->SetText(Status);
    }
    if (PlayButton)
    {
        PlayButton->SetIsEnabled(bCanPlay);
    }
}

void UDerCluePlanningWidget::HandleRecordClicked()
{
    if (Director)
    {
        Director->ToggleRouteRecording();
    }
}

void UDerCluePlanningWidget::HandlePlayClicked()
{
    if (Director)
    {
        Director->PlayRecordedRoute();
    }
}
