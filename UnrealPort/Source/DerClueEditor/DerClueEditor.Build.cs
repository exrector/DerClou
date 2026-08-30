using UnrealBuildTool;

public class DerClueEditor : ModuleRules
{
    public DerClueEditor(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

        PublicDependencyModuleNames.AddRange(new[]
        {
            "Core",
            "CoreUObject",
            "Engine",
            "UnrealEd",
            // The toolset base class and its AICallable contract.
            "ToolsetRegistry",
            // StateTree authoring lives entirely in C++: AddSubTree and friends
            // are plain methods, not UFUNCTIONs, so no script can reach them.
            "StateTreeModule",
            "StateTreeEditorModule"
        });
    }
}
