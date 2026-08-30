#include "Modules/ModuleManager.h"
#include "ToolsetRegistry/UToolsetRegistry.h"

#include "DerClueStateTreeToolset.h"

// Toolsets are not discovered by scanning for UToolsetDefinition subclasses;
// each one is registered explicitly by its owning module, the same way the
// engine's own toolset modules do it.
class FDerClueEditorModule : public IModuleInterface
{
    virtual void StartupModule() override
    {
        UToolsetRegistry::RegisterToolsetClass(UDerClueStateTreeToolset::StaticClass());
    }

    virtual void ShutdownModule() override
    {
        UToolsetRegistry::UnregisterToolsetClass(UDerClueStateTreeToolset::StaticClass());
    }
};

IMPLEMENT_MODULE(FDerClueEditorModule, DerClueEditor);
