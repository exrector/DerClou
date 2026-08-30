#pragma once

#include "CoreMinimal.h"
#include "ToolsetRegistry/ToolsetDefinition.h"
#include "DerClueStateTreeToolset.generated.h"

class UStateTree;
class UStateTreeState;

/**
 * Authoring tools for StateTree assets.
 *
 * Epic's shipped StateTree toolset is inspection only, because the authoring
 * API (UStateTreeEditorData::AddSubTree, UStateTreeState::AddChildState) is
 * plain C++ rather than UFUNCTION, and the SubTrees array is BlueprintReadOnly.
 * No Python toolset or property edit can reach it, so the wrapper has to live
 * in C++. This exposes the minimum needed to build a tree from an agent:
 * create the asset, add states, and read back what exists.
 */
UCLASS()
class UDerClueStateTreeToolset : public UToolsetDefinition
{
    GENERATED_BODY()

public:
    /**
     * Creates a StateTree asset.
     *
     * @param FolderPath Content folder, e.g. "/Game/DerClue/AI".
     * @param AssetName Name of the new asset.
     * @param SchemaClassPath Schema to author against, e.g.
     *        "/Script/GameplayStateTree.StateTreeComponentSchema". A StateTree
     *        without a schema cannot be edited or compiled.
     * @return The created StateTree, or null on failure.
     */
    UFUNCTION(meta = (AICallable))
    static UStateTree* CreateStateTree(const FString& FolderPath, const FString& AssetName,
        const FString& SchemaClassPath);

    /**
     * Adds a top-level subtree (a root state) to a StateTree.
     *
     * @param StateTree The asset to modify.
     * @param StateName Name of the new subtree.
     * @return The new state, or null on failure.
     */
    UFUNCTION(meta = (AICallable))
    static UStateTreeState* AddSubTree(UStateTree* StateTree, FName StateName);

    /**
     * Adds a child state under an existing state.
     *
     * @param ParentState The state to add under.
     * @param StateName Name of the new child.
     * @return The new state, or null on failure.
     */
    UFUNCTION(meta = (AICallable))
    static UStateTreeState* AddChildState(UStateTreeState* ParentState, FName StateName);

    /**
     * Lists the names of a StateTree's top-level subtrees.
     *
     * @param StateTree The asset to inspect.
     * @return Subtree names in order.
     */
    UFUNCTION(meta = (AICallable))
    static TArray<FString> GetSubTreeNames(UStateTree* StateTree);

    /**
     * Saves a StateTree asset to disk.
     *
     * @param StateTree The asset to save.
     * @return True if it was saved.
     */
    UFUNCTION(meta = (AICallable))
    static bool SaveStateTree(UStateTree* StateTree);
};
