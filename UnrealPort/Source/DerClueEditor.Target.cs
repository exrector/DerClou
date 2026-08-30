using UnrealBuildTool;
using System.Collections.Generic;

public class DerClueEditorTarget : TargetRules
{
    public DerClueEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.V7;
        IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
        ExtraModuleNames.Add("DerClue");
    }
}
