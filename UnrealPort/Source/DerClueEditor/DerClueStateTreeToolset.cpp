#include "DerClueStateTreeToolset.h"

#include "AssetToolsModule.h"
#include "IAssetTools.h"
#include "FileHelpers.h"
#include "StateTree.h"
#include "StateTreeEditorData.h"
#include "StateTreeFactory.h"
#include "StateTreeState.h"
#include "UObject/Package.h"

namespace
{
    // UStateTreeEditorData::GetEditorData is a UFUNCTION without UE_API, so it
    // is not linkable from another module. The asset exposes the same object as
    // a plain UPROPERTY, which is exported.
    UStateTreeEditorData* GetEditorDataFor(UStateTree* StateTree)
    {
#if WITH_EDITORONLY_DATA
        return StateTree ? Cast<UStateTreeEditorData>(StateTree->EditorData) : nullptr;
#else
        return nullptr;
#endif
    }
}

UStateTree* UDerClueStateTreeToolset::CreateStateTree(const FString& FolderPath,
    const FString& AssetName, const FString& SchemaClassPath)
{
    // A StateTree without a schema opens but cannot be edited or compiled, so
    // refuse early rather than producing a dead asset.
    UClass* SchemaClass = LoadClass<UObject>(nullptr, *SchemaClassPath);
    if (!SchemaClass)
    {
        UE_LOG(LogTemp, Error, TEXT("DerClue: schema class '%s' not found."), *SchemaClassPath);
        return nullptr;
    }

    UStateTreeFactory* Factory = NewObject<UStateTreeFactory>();
    Factory->SetSchemaClass(SchemaClass);

    IAssetTools& AssetTools = FModuleManager::LoadModuleChecked<FAssetToolsModule>("AssetTools").Get();
    UObject* Created = AssetTools.CreateAsset(AssetName, FolderPath,
        UStateTree::StaticClass(), Factory);
    return Cast<UStateTree>(Created);
}

UStateTreeState* UDerClueStateTreeToolset::AddSubTree(UStateTree* StateTree, FName StateName)
{
    if (!StateTree)
    {
        return nullptr;
    }
    UStateTreeEditorData* EditorData = GetEditorDataFor(StateTree);
    if (!EditorData)
    {
        UE_LOG(LogTemp, Error, TEXT("DerClue: StateTree '%s' has no editor data."),
            *StateTree->GetName());
        return nullptr;
    }
    EditorData->Modify();
    UStateTreeState& NewState = EditorData->AddSubTree(StateName);
    StateTree->MarkPackageDirty();
    return &NewState;
}

UStateTreeState* UDerClueStateTreeToolset::AddChildState(UStateTreeState* ParentState, FName StateName)
{
    if (!ParentState)
    {
        return nullptr;
    }
    ParentState->Modify();
    UStateTreeState& NewState = ParentState->AddChildState(StateName);
    ParentState->MarkPackageDirty();
    return &NewState;
}

TArray<FString> UDerClueStateTreeToolset::GetSubTreeNames(UStateTree* StateTree)
{
    TArray<FString> Names;
    if (!StateTree)
    {
        return Names;
    }
    if (const UStateTreeEditorData* EditorData = GetEditorDataFor(StateTree))
    {
        for (const TObjectPtr<UStateTreeState>& State : EditorData->SubTrees)
        {
            Names.Add(State ? State->Name.ToString() : TEXT("<null>"));
        }
    }
    return Names;
}

bool UDerClueStateTreeToolset::SaveStateTree(UStateTree* StateTree)
{
    if (!StateTree)
    {
        return false;
    }
    UPackage* Package = StateTree->GetOutermost();
    return UEditorLoadingAndSavingUtils::SavePackages({ Package }, /*bOnlyDirty*/ false);
}
