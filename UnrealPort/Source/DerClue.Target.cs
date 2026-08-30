using UnrealBuildTool;
using System.Collections.Generic;

public class DerClueTarget : TargetRules
{
    public DerClueTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Game;
        DefaultBuildSettings = BuildSettingsVersion.V7;
        IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
        ExtraModuleNames.Add("DerClue");
    }
}
