#include "DerCluePlanningWidget.h"

#include "DerClueRuntimeDirector.h"
#include "Blueprint/WidgetTree.h"
#include "Components/Button.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/TextBlock.h"

void UDerCluePlanningWidget::NativeConstruct()
{
    Super::NativeConstruct();
    if (!WidgetTree || WidgetTree->RootWidget)
    {
        return;
    }

    UCanvasPanel* Canvas = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass());
    WidgetTree->RootWidget = Canvas;
    UHorizontalBox* Controls = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass());
    UCanvasPanelSlot* ControlsSlot = Canvas->AddChildToCanvas(Controls);
    ControlsSlot->SetAnchors(FAnchors(0.5f, 1.0f));
    ControlsSlot->SetAlignment(FVector2D(0.5f, 1.0f));
    ControlsSlot->SetPosition(FVector2D(0.0f, -24.0f));
    ControlsSlot->SetAutoSize(true);

    RecordButton = WidgetTree->ConstructWidget<UButton>(UButton::StaticClass());
    RecordButton->SetBackgroundColor(FLinearColor(0.55f, 0.05f, 0.04f, 0.95f));
    RecordText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
    RecordText->SetText(FText::FromString(TEXT("RECORD")));
    RecordText->SetColorAndOpacity(FSlateColor(FLinearColor::White));
    RecordText->SetJustification(ETextJustify::Center);
    RecordButton->AddChild(RecordText);
    UHorizontalBoxSlot* RecordSlot = Controls->AddChildToHorizontalBox(RecordButton);
    RecordSlot->SetPadding(FMargin(8.0f));

    PlayButton = WidgetTree->ConstructWidget<UButton>(UButton::StaticClass());
    PlayButton->SetBackgroundColor(FLinearColor(0.04f, 0.35f, 0.08f, 0.95f));
    UTextBlock* PlayText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
    PlayText->SetText(FText::FromString(TEXT("PLAY")));
    PlayText->SetColorAndOpacity(FSlateColor(FLinearColor::White));
    PlayText->SetJustification(ETextJustify::Center);
    PlayButton->AddChild(PlayText);
    UHorizontalBoxSlot* PlaySlot = Controls->AddChildToHorizontalBox(PlayButton);
    PlaySlot->SetPadding(FMargin(8.0f));

    StatusText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
    StatusText->SetText(FText::FromString(TEXT("FREE TEST")));
    StatusText->SetColorAndOpacity(FSlateColor(FLinearColor::White));
    UHorizontalBoxSlot* StatusSlot = Controls->AddChildToHorizontalBox(StatusText);
    StatusSlot->SetPadding(FMargin(12.0f, 8.0f));

    RecordButton->OnClicked.AddDynamic(this, &UDerCluePlanningWidget::HandleRecordClicked);
    PlayButton->OnClicked.AddDynamic(this, &UDerCluePlanningWidget::HandlePlayClicked);
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
