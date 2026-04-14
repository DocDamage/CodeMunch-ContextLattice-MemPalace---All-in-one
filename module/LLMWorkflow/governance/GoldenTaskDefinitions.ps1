<#
.SYNOPSIS
    Predefined golden tasks for the LLM Workflow governance system.

.DESCRIPTION
    This module contains the task definitions used for regression testing
    and quality assurance. Moving these to a separate file reduces the
    complexity of the core governance engine.
#>

function Get-PredefinedGoldenTasks {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$PackId = ''
    )

    begin {
        $allTasks = @()
    }

    process {
        #=======================================================================
        # RPG Maker MZ Golden Tasks (10 tasks)
        #=======================================================================
        $rpgmakerTasks = @(
            # Task 1: Plugin Skeleton Generation
            (New-GoldenTask `
                -TaskId "gt-rpgmaker-mz-001" `
                -Name "Plugin skeleton generation" `
                -Description "Generate minimal plugin skeleton with one command and one parameter" `
                -PackId "rpgmaker-mz" `
                -Category "codegen" `
                -Difficulty "easy" `
                -Query "Generate a plugin skeleton with one command called 'HealAll' that takes a 'percent' parameter" `
                -ExpectedResult @{
                    containsCommand = "HealAll"
                    containsParameter = "percent"
                    hasJSDocHeader = $true
                    hasPluginCommandRegistration = $true
                } `
                -RequiredEvidence @(
                    @{ source = "rpgmaker-mz-core"; type = "plugin-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("containsCommand", "containsParameter")
                    forbiddenPatterns = @("eval\s*\(", "Function\s*\(")
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "plugin", "skeleton", "javascript")
            ),

            # Task 2: Plugin Conflict Diagnosis
            (New-GoldenTask `
                -TaskId "gt-rpgmaker-mz-002" `
                -Name "Plugin conflict diagnosis" `
                -Description "Diagnose whether two plugins conflict and cite touched methods" `
                -PackId "rpgmaker-mz" `
                -Category "diagnosis" `
                -Difficulty "medium" `
                -Query "Analyze whether VisuStella's Battle Core conflicts with Yanfly's Buff States Core. List any method overlaps and potential conflicts." `
                -ExpectedResult @{
                    analyzesConflict = $true
                    citesMethods = $true
                    providesResolution = $true
                    mentionsLoadOrder = $true
                } `
                -RequiredEvidence @(
                    @{ source = "plugin-compatibility"; type = "method-citation" }
                    @{ source = "battle-core"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("analyzesConflict", "citesMethods")
                    forbiddenPatterns = @()
                    minConfidence = 0.75
                } `
                -Tags @("diagnosis", "conflict", "compatibility", "analysis")
            ),

            # Task 3: Notetag Extraction
            (New-GoldenTask `
                -TaskId "gt-rpgmaker-mz-003" `
                -Name "Notetag extraction from source" `
                -Description "Extract all notetags from a source repository" `
                -PackId "rpgmaker-mz" `
                -Category "extraction" `
                -Difficulty "easy" `
                -Query "Extract all notetags used in the rpg_core.js file and categorize them by type (actor, item, skill, etc.)" `
                -ExpectedResult @{
                    extractsNotetags = $true
                    categorizesByType = $true
                    providesExamples = $true
                    hasValidRegexPatterns = $true
                } `
                -RequiredEvidence @(
                    @{ source = "rpg_core.js"; type = "notetag" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("extractsNotetags", "categorizesByType")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("extraction", "notetag", "parsing", "documentation")
            ),

            # Task 4: Engine Surface Patch Analysis
            (New-GoldenTask `
                -TaskId "gt-rpgmaker-mz-004" `
                -Name "Engine surface patch analysis" `
                -Description "Analyze how a project-local plugin patches a specific engine surface" `
                -PackId "rpgmaker-mz" `
                -Category "analysis" `
                -Difficulty "hard" `
                -Query "Explain how a local plugin that overrides Game_Actor.prototype.paramPlus patches the engine's parameter calculation surface. Include the method chain affected." `
                -ExpectedResult @{
                    identifiesMethodChain = $true
                    explainsPatchMechanism = $true
                    mentionsAliasPattern = $true
                    showsOriginalVsPatched = $true
                } `
                -RequiredEvidence @(
                    @{ source = "Game_Actor"; type = "method-citation" }
                    @{ source = "paramPlus"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("identifiesMethodChain", "explainsPatchMechanism", "mentionsAliasPattern")
                    forbiddenPatterns = @()
                    minConfidence = 0.85
                } `
                -Tags @("analysis", "patching", "prototype", "alias", "advanced")
            ),

            # Task 5: Command Alias Detection
            (New-GoldenTask `
                -TaskId "gt-rpgmaker-mz-005" `
                -Name "Command alias detection" `
                -Description "Detect and explain command aliases used in plugin development" `
                -PackId "rpgmaker-mz" `
                -Category "analysis" `
                -Difficulty "medium" `
                -Query "What are the common command aliases used in RPG Maker MZ plugins? Explain how PluginManager.registerCommand relates to alias patterns." `
                -ExpectedResult @{
                    identifiesAliases = $true
                    explainsRegisterCommand = $true
                    providesExamples = $true
                    mentionsArguments = $true
                } `
                -RequiredEvidence @(
                    @{ source = "PluginManager"; type = "method-citation" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("identifiesAliases", "explainsRegisterCommand")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("analysis", "alias", "command", "plugin-manager")
            ),

            # Task 6: Plugin Parameter Validation
            (New-GoldenTask `
                -TaskId "gt-rpgmaker-mz-006" `
                -Name "Plugin parameter validation" `
                -Description "Validate and parse plugin parameters with type checking" `
                -PackId "rpgmaker-mz" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Write code to parse and validate plugin parameters including number, string, boolean, and struct types with proper defaults." `
                -ExpectedResult @{
                    handlesNumberParams = $true
                    handlesBooleanParams = $true
                    handlesStringParams = $true
                    handlesStructParams = $true
                    providesDefaults = $true
                    usesPluginManager = $true
                } `
                -RequiredEvidence @(
                    @{ source = "PluginManager"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("handlesNumberParams", "handlesBooleanParams", "providesDefaults")
                    forbiddenPatterns = @("eval\s*\(")
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "parameters", "validation", "parsing")
            ),

            # Task 7: Event Script Conversion
            (New-GoldenTask `
                -TaskId "gt-rpgmaker-mz-007" `
                -Name "Event script conversion" `
                -Description "Convert event commands to equivalent script calls" `
                -PackId "rpgmaker-mz" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Convert the event command 'Change Gold +100' to its equivalent JavaScript code using `$gameParty.gainGold()" `
                -ExpectedResult @{
                    usesCorrectMethod = $true
                    usesCorrectAmount = $true
                    explainsEventCommand = $true
                    providesAlternative = $true
                } `
                -RequiredEvidence @(
                    @{ source = "Game_Party"; type = "method-citation" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("usesCorrectMethod", "explainsEventCommand")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "event", "script-call", "conversion")
            ),

            # Task 8: Animation Sequence Generation
            (New-GoldenTask `
                -TaskId "gt-rpgmaker-mz-008" `
                -Name "Animation sequence generation" `
                -Description "Generate animation sequences using Action Sequence patterns" `
                -PackId "rpgmaker-mz" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Create an action sequence that makes the user step forward, perform an attack animation, shake the screen, and return to base position." `
                -ExpectedResult @{
                    hasStepForward = $true
                    hasAttackMotion = $true
                    hasScreenShake = $true
                    hasReturnMotion = $true
                    usesCorrectSyntax = $true
                } `
                -RequiredEvidence @(
                    @{ source = "action-sequence"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("hasStepForward", "hasAttackMotion", "hasReturnMotion")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "animation", "action-sequence", "battle")
            ),

            # Task 9: Save System Customization
            (New-GoldenTask `
                -TaskId "gt-rpgmaker-mz-009" `
                -Name "Save system customization" `
                -Description "Add custom data to the save file system" `
                -PackId "rpgmaker-mz" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Show how to add custom data to save files by extending DataManager and hooking into makeSaveContents and extractSaveContents." `
                -ExpectedResult @{
                    extendsDataManager = $true
                    overridesMakeSaveContents = $true
                    overridesExtractSaveContents = $true
                    preservesExistingData = $true
                    usesAliasPattern = $true
                } `
                -RequiredEvidence @(
                    @{ source = "DataManager"; type = "method-citation" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("extendsDataManager", "overridesMakeSaveContents", "usesAliasPattern")
                    forbiddenPatterns = @("eval\s*\(")
                    minConfidence = 0.85
                } `
                -Tags @("codegen", "save-system", "data-manager", "advanced")
            ),

            # Task 10: Menu Scene Extension
            (New-GoldenTask `
                -TaskId "gt-rpgmaker-mz-010" `
                -Name "Menu scene extension" `
                -Description "Extend the main menu with custom commands" `
                -PackId "rpgmaker-mz" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Add a custom 'Bestiary' command to the main menu that opens a custom scene. Include the Scene_Menu modification." `
                -ExpectedResult @{
                    addsMenuCommand = $true
                    createsCustomScene = $true
                    handlesWindowCommand = $true
                    integratesWithSceneMenu = $true
                } `
                -RequiredEvidence @(
                    @{ source = "Scene_Menu"; type = "source-reference" }
                    @{ source = "Window_MenuCommand"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("addsMenuCommand", "createsCustomScene", "integratesWithSceneMenu")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "menu", "scene", "window")
            )
        )

        #=======================================================================
        # Godot Engine Golden Tasks (10 tasks)
        #=======================================================================
        $godotTasks = @(
            # Task 1: GDScript Class Generation
            (New-GoldenTask `
                -TaskId "gt-godot-001" `
                -Name "GDScript class generation" `
                -Description "Generate a GDScript class with proper structure" `
                -PackId "godot" `
                -Category "codegen" `
                -Difficulty "easy" `
                -Query "Generate a GDScript class called 'PlayerController' that extends CharacterBody2D with a speed property and _physics_process method" `
                -ExpectedResult @{
                    extendsCharacterBody2D = $true
                    hasClassName = "PlayerController"
                    hasSpeedProperty = $true
                    hasPhysicsProcess = $true
                    usesGDScriptSyntax = $true
                } `
                -RequiredEvidence @(
                    @{ source = "godot-api"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("hasClassName", "hasSpeedProperty", "hasPhysicsProcess")
                    forbiddenPatterns = @("public class", "def ")
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "gdscript", "class", "node")
            ),

            # Task 2: Signal Connection Setup
            (New-GoldenTask `
                -TaskId "gt-godot-002" `
                -Name "Signal connection setup" `
                -Description "Demonstrate proper Godot signal connection patterns" `
                -PackId "godot" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Show three ways to connect a button's pressed signal to a callback function in GDScript, including the @onready pattern" `
                -ExpectedResult @{
                    showsConnectMethod = $true
                    showsEditorConnection = $true
                    showsOnreadyPattern = $true
                    includesSignalCallback = $true
                } `
                -RequiredEvidence @(
                    @{ source = "godot-signals"; type = "signal-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("showsConnectMethod", "showsOnreadyPattern")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "signals", "connection", "gdscript")
            ),

            # Task 3: Autoload Setup
            (New-GoldenTask `
                -TaskId "gt-godot-003" `
                -Name "Autoload (Singleton) setup" `
                -Description "Explain and demonstrate Godot autoload/singleton pattern" `
                -PackId "godot" `
                -Category "codegen" `
                -Difficulty "easy" `
                -Query "Create a GameManager autoload script in GDScript that tracks player score and lives, and show how to access it from another scene" `
                -ExpectedResult @{
                    createsGameManager = $true
                    tracksScoreAndLives = $true
                    showsAutoloadAccess = $true
                    usesGlobalReference = $true
                } `
                -RequiredEvidence @(
                    @{ source = "godot-autoload"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("createsGameManager", "tracksScoreAndLives", "showsAutoloadAccess")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "autoload", "singleton", "global", "gdscript")
            ),

            # Task 4: Scene Inheritance Pattern
            (New-GoldenTask `
                -TaskId "gt-godot-004" `
                -Name "Scene inheritance pattern" `
                -Description "Demonstrate scene inheritance and instance overrides" `
                -PackId "godot" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Explain scene inheritance in Godot with an example: create a base enemy scene and show how to inherit from it to create a specific enemy type." `
                -ExpectedResult @{
                    explainsSceneInheritance = $true
                    showsBaseScene = $true
                    showsInheritedScene = $true
                    explainsEditableChildren = $true
                    mentionsInstanceOverrides = $true
                } `
                -RequiredEvidence @(
                    @{ source = "godot-scenes"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("explainsSceneInheritance", "showsBaseScene", "showsInheritedScene")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "scene", "inheritance", "instancing")
            ),

            # Task 5: Resource Preloading
            (New-GoldenTask `
                -TaskId "gt-godot-005" `
                -Name "Resource preloading" `
                -Description "Demonstrate proper resource loading and preloading patterns" `
                -PackId "godot" `
                -Category "codegen" `
                -Difficulty "easy" `
                -Query "Show the difference between preload(), load(), and ResourceLoader in GDScript with examples of when to use each." `
                -ExpectedResult @{
                    explainsPreload = $true
                    explainsLoad = $true
                    explainsResourceLoader = $true
                    providesUseCases = $true
                    mentionsEditorVsRuntime = $true
                } `
                -RequiredEvidence @(
                    @{ source = "godot-resources"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("explainsPreload", "explainsLoad", "providesUseCases")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "resources", "preload", "loading")
            ),

            # Task 6: Custom Node Creation
            (New-GoldenTask `
                -TaskId "gt-godot-006" `
                -Name "Custom node creation" `
                -Description "Create a custom node with custom drawing and gizmos" `
                -PackId "godot" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Create a custom Node2D that draws a health bar above the node using _draw(). Include a @tool script for editor visualization." `
                -ExpectedResult @{
                    extendsNode2D = $true
                    implementsDraw = $true
                    usesToolAnnotation = $true
                    drawsHealthBar = $true
                    handlesEditorPreview = $true
                } `
                -RequiredEvidence @(
                    @{ source = "godot-custom-drawing"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("extendsNode2D", "implementsDraw", "drawsHealthBar")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "custom-node", "drawing", "tool")
            ),

            # Task 7: Editor Plugin Development
            (New-GoldenTask `
                -TaskId "gt-godot-007" `
                -Name "Editor plugin development" `
                -Description "Create a simple editor plugin with dock panel" `
                -PackId "godot" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Create a complete Godot editor plugin in GDScript that adds a dock panel with a button. Include the plugin.cfg, plugin.gd, and the dock scene." `
                -ExpectedResult @{
                    hasPluginCfg = $true
                    extendsEditorPlugin = $true
                    hasEnterMethod = $true
                    hasExitMethod = $true
                    addsDockPanel = $true
                    handlesHasMainScreen = $true
                } `
                -RequiredEvidence @(
                    @{ source = "godot-editor-plugin"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("extendsEditorPlugin", "hasEnterMethod", "addsDockPanel")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "editor", "plugin", "dock")
            ),

            # Task 8: Shader Material Setup
            (New-GoldenTask `
                -TaskId "gt-godot-008" `
                -Name "Shader material setup" `
                -Description "Create a custom shader with uniforms and visual effects" `
                -PackId "godot" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Write a Godot shader that creates a pulsing glow effect using TIME uniform. The shader should have a color uniform and work with CanvasItem." `
                -ExpectedResult @{
                    shaderTypeCanvasItem = $true
                    usesTimeUniform = $true
                    hasColorUniform = $true
                    createsPulsingEffect = $true
                    usesProperSyntax = $true
                } `
                -RequiredEvidence @(
                    @{ source = "godot-shaders"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("shaderTypeCanvasItem", "usesTimeUniform", "createsPulsingEffect")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "shader", "visual", "gdshader")
            ),

            # Task 9: Input Action Mapping
            (New-GoldenTask `
                -TaskId "gt-godot-009" `
                -Name "Input action mapping" `
                -Description "Handle input actions with InputMap and remapping" `
                -PackId "godot" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Show how to check for input actions in _process(), and how to programmatically add a new action with keyboard and joypad mappings." `
                -ExpectedResult @{
                    usesIsActionPressed = $true
                    usesInputMapAddAction = $true
                    addsKeyboardEvent = $true
                    addsJoypadEvent = $true
                    explainsInputMapAPI = $true
                } `
                -RequiredEvidence @(
                    @{ source = "godot-input"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("usesIsActionPressed", "usesInputMapAddAction")
                    forbiddenPatterns = @("Input.is_key_pressed")
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "input", "inputmap", "controls")
            ),

            # Task 10: Multiplayer Networking Pattern
            (New-GoldenTask `
                -TaskId "gt-godot-010" `
                -Name "Multiplayer networking pattern" `
                -Description "Implement basic multiplayer with MultiplayerAPI and RPCs" `
                -PackId "godot" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Create a simple multiplayer script using Godot's MultiplayerAPI with @rpc annotation. Include server creation and client connection code." `
                -ExpectedResult @{
                    usesRPCAnnotation = $true
                    usesMultiplayerAPI = $true
                    createsServer = $true
                    connectsClient = $true
                    handlesMultiplayerAuthority = $true
                } `
                -RequiredEvidence @(
                    @{ source = "godot-multiplayer"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("usesRPCAnnotation", "usesMultiplayerAPI")
                    forbiddenPatterns = @("NetworkedMultiplayerENet")
                    minConfidence = 0.75
                } `
                -Tags @("codegen", "multiplayer", "networking", "rpc")
            )
        )

        #=======================================================================
        # Blender Engine Golden Tasks (10 tasks)
        #=======================================================================
        $blenderTasks = @(
            # Task 1: Operator Registration
            (New-GoldenTask `
                -TaskId "gt-blender-001" `
                -Name "Operator registration" `
                -Description "Create a Blender operator with proper registration" `
                -PackId "blender" `
                -Category "codegen" `
                -Difficulty "easy" `
                -Query "Create a Blender Python operator that scales selected objects by a factor property, with proper bl_idname, bl_label, and registration" `
                -ExpectedResult @{
                    hasBlIdname = $true
                    hasBlLabel = $true
                    hasExecuteMethod = $true
                    hasScaleFactorProperty = $true
                    includesRegistration = $true
                } `
                -RequiredEvidence @(
                    @{ source = "blender-api"; type = "bpy-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("hasBlIdname", "hasExecuteMethod", "includesRegistration")
                    forbiddenPatterns = @("class.*\\(.*Operator\\):", "^def.*execute")
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "operator", "addon", "python")
            ),

            # Task 2: Geometry Nodes Setup
            (New-GoldenTask `
                -TaskId "gt-blender-002" `
                -Name "Geometry nodes code generation" `
                -Description "Generate geometry nodes setup using Python API" `
                -PackId "blender" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Write Python code to create a geometry nodes modifier that adds a subdivision surface followed by a set position node with random offset" `
                -ExpectedResult @{
                    createsModifier = $true
                    addsSubdivisionNode = $true
                    addsSetPositionNode = $true
                    usesNodesNew = $true
                    linksNodes = $true
                } `
                -RequiredEvidence @(
                    @{ source = "blender-geometry-nodes"; type = "bpy-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("createsModifier", "addsSubdivisionNode", "usesNodesNew")
                    forbiddenPatterns = @()
                    minConfidence = 0.75
                } `
                -Tags @("codegen", "geometry-nodes", "modifier", "procedural")
            ),

            # Task 3: Addon Manifest
            (New-GoldenTask `
                -TaskId "gt-blender-003" `
                -Name "Addon manifest creation" `
                -Description "Create a complete Blender addon manifest with bl_info" `
                -PackId "blender" `
                -Category "codegen" `
                -Difficulty "easy" `
                -Query "Create a complete Blender addon __init__.py with bl_info dictionary, including name, author, version, blender version, location, description, and category" `
                -ExpectedResult @{
                    hasBlInfo = $true
                    hasNameField = $true
                    hasAuthorField = $true
                    hasVersionTuple = $true
                    hasBlenderVersion = $true
                    hasCategory = $true
                    hasRegistrationFunctions = $true
                } `
                -RequiredEvidence @(
                    @{ source = "blender-addon"; type = "bpy-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("hasBlInfo", "hasVersionTuple", "hasRegistrationFunctions")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "addon", "manifest", "bl_info")
            ),

            # Task 4: Panel Layout Design
            (New-GoldenTask `
                -TaskId "gt-blender-004" `
                -Name "Panel layout design" `
                -Description "Create a custom panel with organized UI layout" `
                -PackId "blender" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Create a Blender panel with a box layout containing properties, a row with aligned buttons, and a column with an enum dropdown. Include proper bl_space_type and bl_region_type." `
                -ExpectedResult @{
                    extendsPanel = $true
                    hasBoxLayout = $true
                    hasRowLayout = $true
                    hasColumnLayout = $true
                    usesProperSpaceType = $true
                    includesDrawMethod = $true
                } `
                -RequiredEvidence @(
                    @{ source = "blender-ui"; type = "bpy-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("extendsPanel", "includesDrawMethod", "usesProperSpaceType")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "panel", "ui", "layout")
            ),

            # Task 5: Property Group Definition
            (New-GoldenTask `
                -TaskId "gt-blender-005" `
                -Name "Property group definition" `
                -Description "Define custom property types with PropertyGroup" `
                -PackId "blender" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Create a PropertyGroup with StringProperty, IntProperty, FloatProperty, BoolProperty, EnumProperty, and PointerProperty. Show how to register it to Scene." `
                -ExpectedResult @{
                    extendsPropertyGroup = $true
                    hasStringProperty = $true
                    hasFloatProperty = $true
                    hasEnumProperty = $true
                    registersToScene = $true
                } `
                -RequiredEvidence @(
                    @{ source = "blender-properties"; type = "bpy-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("extendsPropertyGroup", "registersToScene")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "properties", "property-group", "types")
            ),

            # Task 6: Material Node Setup
            (New-GoldenTask `
                -TaskId "gt-blender-006" `
                -Name "Material node setup" `
                -Description "Create material with nodes using Python API" `
                -PackId "blender" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Write Python code to create a Principled BSDF material, add a noise texture to the base color, and link the nodes properly. Use material.use_nodes = True." `
                -ExpectedResult @{
                    enablesUseNodes = $true
                    createsPrincipledBSDF = $true
                    addsNoiseTexture = $true
                    linksNodes = $true
                    setsOutput = $true
                } `
                -RequiredEvidence @(
                    @{ source = "blender-materials"; type = "bpy-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("enablesUseNodes", "createsPrincipledBSDF", "linksNodes")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "materials", "nodes", "shading")
            ),

            # Task 7: Rigging Automation
            (New-GoldenTask `
                -TaskId "gt-blender-007" `
                -Name "Rigging automation" `
                -Description "Automate bone creation and constraints" `
                -PackId "blender" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Write a Python script that creates an armature with three connected bones (hip, knee, ankle), adds an Inverse Kinematics constraint to the ankle, and sets up proper parenting." `
                -ExpectedResult @{
                    createsArmature = $true
                    editsBones = $true
                    createsConnectedChain = $true
                    addsIKConstraint = $true
                    setsBoneHierarchy = $true
                } `
                -RequiredEvidence @(
                    @{ source = "blender-armature"; type = "bpy-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("createsArmature", "editsBones", "addsIKConstraint")
                    forbiddenPatterns = @()
                    minConfidence = 0.75
                } `
                -Tags @("codegen", "rigging", "armature", "constraints")
            ),

            # Task 8: Render Pipeline Configuration
            (New-GoldenTask `
                -TaskId "gt-blender-008" `
                -Name "Render pipeline configuration" `
                -Description "Configure render settings programmatically" `
                -PackId "blender" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Set up Blender render settings using Python: enable cycles, set samples to 128, set resolution to 1920x1080 at 100%, enable denoising, and set output format to PNG." `
                -ExpectedResult @{
                    setsEngineCycles = $true
                    setsSamples = $true
                    setsResolution = $true
                    enablesDenoising = $true
                    setsOutputFormat = $true
                } `
                -RequiredEvidence @(
                    @{ source = "blender-render"; type = "bpy-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("setsEngineCycles", "setsSamples", "setsResolution")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "render", "cycles", "settings")
            ),

            # Task 9: Import/Export Operator
            (New-GoldenTask `
                -TaskId "gt-blender-009" `
                -Name "Import/export operator" `
                -Description "Create custom import/export operator with file selector" `
                -PackId "blender" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Create a Blender operator that exports selected mesh objects to a custom JSON format. Include a file selector with .json filter and iterate through mesh data." `
                -ExpectedResult @{
                    extendsOperator = $true
                    hasFilepathProperty = $true
                    usesFilterGlob = $true
                    iteratesSelected = $true
                    exportsMeshData = $true
                } `
                -RequiredEvidence @(
                    @{ source = "blender-io"; type = "bpy-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("extendsOperator", "hasFilepathProperty", "exportsMeshData")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "import-export", "file-io", "mesh")
            ),

            # Task 10: Custom Keymap Binding
            (New-GoldenTask `
                -TaskId "gt-blender-010" `
                -Name "Custom keymap binding" `
                -Description "Add custom hotkeys and keymap entries" `
                -PackId "blender" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Show how to add a custom keymap entry in Blender Python that calls an operator when pressing Ctrl+Shift+T in the 3D viewport. Include addon registration code." `
                -ExpectedResult @{
                    accessesKeymaps = $true
                    addsKeymapItem = $true
                    setsKeyConfig = $true
                    usesCorrectModifier = $true
                    registersWithAddon = $true
                } `
                -RequiredEvidence @(
                    @{ source = "blender-keymap"; type = "bpy-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("accessesKeymaps", "addsKeymapItem", "registersWithAddon")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "keymap", "hotkey", "shortcut")
            )
        )

        #=======================================================================
        # API Reverse Tooling Pack Golden Tasks (10 tasks)
        #=======================================================================
        $apiReverseTasks = @(
            # Task 1: API Endpoint Discovery
            (New-GoldenTask `
                -TaskId "gt-api-reverse-001" `
                -Name "API endpoint discovery" `
                -Description "Discover and catalog API endpoints from traffic or documentation" `
                -PackId "api-reverse" `
                -Category "analysis" `
                -Difficulty "medium" `
                -Query "Analyze HTTP traffic logs to discover REST API endpoints, extract their paths, HTTP methods, and identify resource patterns. Return a structured catalog." `
                -ExpectedResult @{
                    identifiesEndpoints = $true
                    extractsHttpMethods = $true
                    recognizesResourcePatterns = $true
                    structuresCatalog = $true
                    identifiesBaseUrl = $true
                } `
                -RequiredEvidence @(
                    @{ source = "http-traffic"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("identifiesEndpoints", "extractsHttpMethods", "recognizesResourcePatterns")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("api", "discovery", "endpoints", "rest", "traffic-analysis")
            ),

            # Task 2: Schema Inference from Traffic
            (New-GoldenTask `
                -TaskId "gt-api-reverse-002" `
                -Name "Schema inference from traffic" `
                -Description "Infer data schemas from API request/response payloads" `
                -PackId "api-reverse" `
                -Category "analysis" `
                -Difficulty "medium" `
                -Query "Given sample JSON request/response payloads from an API, infer the complete data schemas including types, required fields, and nested structures." `
                -ExpectedResult @{
                    infersTypes = $true
                    identifiesRequiredFields = $true
                    handlesNestedStructures = $true
                    detectsEnums = $true
                    providesJsonSchema = $true
                } `
                -RequiredEvidence @(
                    @{ source = "json-payloads"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("infersTypes", "identifiesRequiredFields", "providesJsonSchema")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("api", "schema", "inference", "json", "types")
            ),

            # Task 3: OpenAPI Spec Generation
            (New-GoldenTask `
                -TaskId "gt-api-reverse-003" `
                -Name "OpenAPI spec generation" `
                -Description "Generate complete OpenAPI 3.0 specification from API analysis" `
                -PackId "api-reverse" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Generate a complete OpenAPI 3.0 specification document from discovered endpoints, schemas, and authentication requirements. Include paths, components, and security schemes." `
                -ExpectedResult @{
                    validOpenApiStructure = $true
                    includesPaths = $true
                    includesComponents = $true
                    includesSecuritySchemes = $true
                    hasInfoSection = $true
                    hasOpenApiVersion = $true
                } `
                -RequiredEvidence @(
                    @{ source = "openapi"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("validOpenApiStructure", "includesPaths", "includesComponents")
                    forbiddenPatterns = @()
                    minConfidence = 0.85
                } `
                -Tags @("api", "openapi", "spec", "documentation", "swagger")
            ),

            # Task 4: Authentication Pattern Detection
            (New-GoldenTask `
                -TaskId "gt-api-reverse-004" `
                -Name "Authentication pattern detection" `
                -Description "Identify and classify API authentication mechanisms" `
                -PackId "api-reverse" `
                -Category "analysis" `
                -Difficulty "medium" `
                -Query "Analyze HTTP headers and request patterns to identify authentication mechanisms (API keys, OAuth, JWT, Basic Auth, Bearer tokens) and extract their usage patterns." `
                -ExpectedResult @{
                    identifiesAuthType = $true
                    extractsApiKeys = $true
                    detectsOAuthFlows = $true
                    recognizesJwtPattern = $true
                    documentsAuthLocation = $true
                } `
                -RequiredEvidence @(
                    @{ source = "http-headers"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("identifiesAuthType", "documentsAuthLocation")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("api", "authentication", "oauth", "jwt", "security")
            ),

            # Task 5: GraphQL Introspection
            (New-GoldenTask `
                -TaskId "gt-api-reverse-005" `
                -Name "GraphQL introspection" `
                -Description "Parse and analyze GraphQL schema introspection results" `
                -PackId "api-reverse" `
                -Category "analysis" `
                -Difficulty "medium" `
                -Query "Parse GraphQL introspection query results to extract types, queries, mutations, subscriptions, and their relationships. Generate a navigable schema documentation." `
                -ExpectedResult @{
                    extractsTypes = $true
                    identifiesQueries = $true
                    identifiesMutations = $true
                    identifiesSubscriptions = $true
                    mapsRelationships = $true
                    handlesInterfaces = $true
                } `
                -RequiredEvidence @(
                    @{ source = "graphql-schema"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("extractsTypes", "identifiesQueries", "identifiesMutations")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("api", "graphql", "introspection", "schema")
            ),

            # Task 6: gRPC Proto Reconstruction
            (New-GoldenTask `
                -TaskId "gt-api-reverse-006" `
                -Name "gRPC proto reconstruction" `
                -Description "Reconstruct protobuf definitions from gRPC traffic or reflection" `
                -PackId "api-reverse" `
                -Category "analysis" `
                -Difficulty "hard" `
                -Query "Reconstruct .proto file definitions from gRPC method calls, message patterns, and field types observed in binary traffic or server reflection." `
                -ExpectedResult @{
                    reconstructsServices = $true
                    definesMessages = $true
                    infersFieldTypes = $true
                    assignsFieldNumbers = $true
                    generatesValidProto = $true
                } `
                -RequiredEvidence @(
                    @{ source = "grpc-traffic"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("reconstructsServices", "definesMessages", "generatesValidProto")
                    forbiddenPatterns = @()
                    minConfidence = 0.85
                } `
                -Tags @("api", "grpc", "protobuf", "proto", "binary")
            ),

            # Task 7: Response Validation
            (New-GoldenTask `
                -TaskId "gt-api-reverse-007" `
                -Name "Response validation" `
                -Description "Validate API responses against inferred or provided schemas" `
                -PackId "api-reverse" `
                -Category "validation" `
                -Difficulty "medium" `
                -Query "Given API responses and a schema, validate conformance checking for required fields, data types, value constraints, and nested structure compliance." `
                -ExpectedResult @{
                    validatesRequiredFields = $true
                    checksDataTypes = $true
                    validatesConstraints = $true
                    reportsValidationErrors = $true
                    providesErrorLocations = $true
                } `
                -RequiredEvidence @(
                    @{ source = "api-responses"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("validatesRequiredFields", "checksDataTypes", "reportsValidationErrors")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("api", "validation", "schema", "response", "conformance")
            ),

            # Task 8: Rate Limit Analysis
            (New-GoldenTask `
                -TaskId "gt-api-reverse-008" `
                -Name "Rate limit analysis" `
                -Description "Extract and analyze rate limiting headers and policies" `
                -PackId "api-reverse" `
                -Category "analysis" `
                -Difficulty "easy" `
                -Query "Analyze HTTP response headers (X-RateLimit, Retry-After, etc.) to extract rate limit policies, current usage, reset times, and recommended throttling strategies." `
                -ExpectedResult @{
                    extractsRateLimitHeaders = $true
                    identifiesLimitValues = $true
                    extractsResetTimes = $true
                    calculatesRemainingQuota = $true
                    suggestsThrottling = $true
                } `
                -RequiredEvidence @(
                    @{ source = "rate-limit-headers"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("extractsRateLimitHeaders", "identifiesLimitValues", "calculatesRemainingQuota")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("api", "rate-limit", "throttling", "headers", "policy")
            ),

            # Task 9: Error Pattern Recognition
            (New-GoldenTask `
                -TaskId "gt-api-reverse-009" `
                -Name "Error pattern recognition" `
                -Description "Identify and classify API error response patterns" `
                -PackId "api-reverse" `
                -Category "analysis" `
                -Difficulty "medium" `
                -Query "Analyze API error responses to identify error patterns, status code distributions, error code taxonomies, and extract meaningful error messages and recovery hints." `
                -ExpectedResult @{
                    categorizesHttpStatusCodes = $true
                    extractsErrorCodes = $true
                    identifiesErrorPatterns = $true
                    extractsErrorMessages = $true
                    suggestsRecoveryActions = $true
                } `
                -RequiredEvidence @(
                    @{ source = "error-responses"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("categorizesHttpStatusCodes", "extractsErrorCodes", "identifiesErrorPatterns")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("api", "errors", "patterns", "status-codes", "recovery")
            ),

            # Task 10: API Changelog Detection
            (New-GoldenTask `
                -TaskId "gt-api-reverse-010" `
                -Name "API changelog detection" `
                -Description "Detect changes between API versions by comparing specs or traffic" `
                -PackId "api-reverse" `
                -Category "comparison" `
                -Difficulty "hard" `
                -Query "Compare two versions of an API specification or traffic logs to detect breaking changes, new endpoints, deprecated fields, and generate a detailed changelog." `
                -ExpectedResult @{
                    identifiesBreakingChanges = $true
                    detectsNewEndpoints = $true
                    identifiesDeprecatedFields = $true
                    detectsTypeChanges = $true
                    generatesDetailedChangelog = $true
                    classifiesChangeSeverity = $true
                } `
                -RequiredEvidence @(
                    @{ source = "api-versions"; type = "comparison" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("identifiesBreakingChanges", "detectsNewEndpoints", "generatesDetailedChangelog")
                    forbiddenPatterns = @()
                    minConfidence = 0.85
                } `
                -Tags @("api", "changelog", "versioning", "breaking-changes", "diff")
            )
        )

        #=======================================================================
        # Notebook/Data Workflow Pack Golden Tasks (10 tasks)
        #=======================================================================
        $notebookDataTasks = @(
            # Task 1: Notebook Version Control
            (New-GoldenTask `
                -TaskId "gt-notebook-data-001" `
                -Name "Notebook version control" `
                -Description "Implement version control strategies for Jupyter notebooks" `
                -PackId "notebook-data" `
                -Category "integration" `
                -Difficulty "medium" `
                -Query "Show how to configure Git for Jupyter notebooks including cleaning output, using nbstripout, creating .gitattributes, and handling notebook diffs effectively." `
                -ExpectedResult @{
                    configuresGitAttributes = $true
                    mentionsNbstripout = $true
                    handlesOutputCleaning = $true
                    suggestsDiffTools = $true
                    providesPreCommitHooks = $true
                } `
                -RequiredEvidence @(
                    @{ source = "jupyter-git"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("configuresGitAttributes", "handlesOutputCleaning")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("notebook", "jupyter", "git", "version-control", "nbstripout")
            ),

            # Task 2: Cell Output Caching
            (New-GoldenTask `
                -TaskId "gt-notebook-data-002" `
                -Name "Cell output caching" `
                -Description "Implement caching mechanisms for expensive cell computations" `
                -PackId "notebook-data" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Write Python code to implement cell output caching in Jupyter using @lru_cache, joblib.Memory, or ipycache to avoid re-running expensive computations." `
                -ExpectedResult @{
                    implementsCachingDecorator = $true
                    handlesCacheInvalidation = $true
                    showsJoblibMemory = $true
                } `
                -RequiredEvidence @(
                    @{ source = "python-cache"; type = "method-citation" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("implementsCachingDecorator", "handlesCacheInvalidation")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("notebook", "caching", "jupyter", "performance", "memoization")
            ),

            # Task 3: Data Lineage Tracking
            (New-GoldenTask `
                -TaskId "gt-notebook-data-003" `
                -Name "Data lineage tracking" `
                -Description "Track data flow and transformations through notebook cells" `
                -PackId "notebook-data" `
                -Category "analysis" `
                -Difficulty "hard" `
                -Query "Design a data lineage tracking system for Jupyter notebooks that captures variable dependencies, cell execution order, and data transformation chains." `
                -ExpectedResult @{
                    tracksVariableDependencies = $true
                    capturesExecutionOrder = $true
                    mapsDataTransformations = $true
                    providesLineageGraph = $true
                    handlesCellReruns = $true
                } `
                -RequiredEvidence @(
                    @{ source = "data-lineage"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("tracksVariableDependencies", "capturesExecutionOrder", "mapsDataTransformations")
                    forbiddenPatterns = @()
                    minConfidence = 0.85
                } `
                -Tags @("notebook", "lineage", "dataflow", "tracking", "provenance")
            ),

            # Task 4: Pipeline Dependency Graph
            (New-GoldenTask `
                -TaskId "gt-notebook-data-004" `
                -Name "Pipeline dependency graph" `
                -Description "Build and visualize data pipeline dependency graphs" `
                -PackId "notebook-data" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Create Python code to build a dependency graph for a data processing pipeline using networkx, showing stages, dependencies, and generating a visual diagram." `
                -ExpectedResult @{
                    buildsDependencyGraph = $true
                    identifiesPipelineStages = $true
                    visualizesGraph = $true
                    detectsCycles = $true
                    showsExecutionOrder = $true
                } `
                -RequiredEvidence @(
                    @{ source = "networkx"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("buildsDependencyGraph", "identifiesPipelineStages", "visualizesGraph")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("notebook", "pipeline", "dependency-graph", "visualization", "dag")
            ),

            # Task 5: Data Validation Rules
            (New-GoldenTask `
                -TaskId "gt-notebook-data-005" `
                -Name "Data validation rules" `
                -Description "Implement comprehensive data validation for dataframes" `
                -PackId "notebook-data" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Write Python code using pydantic, pandera, or great_expectations to validate pandas DataFrames with schema checks, constraints, and custom validation rules." `
                -ExpectedResult @{
                    definesSchemaConstraints = $true
                    validatesDataTypes = $true
                    checksNullValues = $true
                    validatesRanges = $true
                    providesValidationReport = $true
                } `
                -RequiredEvidence @(
                    @{ source = "pandas-validation"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("definesSchemaConstraints", "validatesDataTypes", "providesValidationReport")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("notebook", "validation", "pandas", "schema", "data-quality")
            ),

            # Task 6: Visualization Generation
            (New-GoldenTask `
                -TaskId "gt-notebook-data-006" `
                -Name "Visualization generation" `
                -Description "Generate data visualizations optimized for notebooks" `
                -PackId "notebook-data" `
                -Category "codegen" `
                -Difficulty "easy" `
                -Query "Create Python code to generate matplotlib, seaborn, and plotly visualizations optimized for Jupyter notebooks with proper sizing, interactivity, and display settings." `
                -ExpectedResult @{
                    usesMatplotlib = $true
                    usesSeaborn = $true
                    usesPlotly = $true
                    optimizesForNotebook = $true
                    handlesInteractivePlots = $true
                    setsProperFigureSize = $true
                } `
                -RequiredEvidence @(
                    @{ source = "visualization"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("usesMatplotlib", "optimizesForNotebook")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("notebook", "visualization", "matplotlib", "plotly", "seaborn")
            ),

            # Task 7: Dataset Profiling
            (New-GoldenTask `
                -TaskId "gt-notebook-data-007" `
                -Name "Dataset profiling" `
                -Description "Generate comprehensive dataset profiling reports" `
                -PackId "notebook-data" `
                -Category "analysis" `
                -Difficulty "easy" `
                -Query "Use ydata-profiling, sweetviz, or pandas-profiling to generate a comprehensive dataset report including statistics, distributions, correlations, and data quality alerts." `
                -ExpectedResult @{
                    generatesProfileReport = $true
                    includesStatistics = $true
                    showsDistributions = $true
                    analyzesCorrelations = $true
                    flagsDataQualityIssues = $true
                } `
                -RequiredEvidence @(
                    @{ source = "profiling"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("generatesProfileReport", "includesStatistics", "flagsDataQualityIssues")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("notebook", "profiling", "eda", "data-quality", "statistics")
            ),

            # Task 8: Feature Engineering Pipeline
            (New-GoldenTask `
                -TaskId "gt-notebook-data-008" `
                -Name "Feature engineering pipeline" `
                -Description "Build reusable feature engineering pipelines with sklearn" `
                -PackId "notebook-data" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Create a scikit-learn Pipeline with ColumnTransformer for feature engineering including scaling, encoding, text vectorization, and custom transformers." `
                -ExpectedResult @{
                    usesPipeline = $true
                    usesColumnTransformer = $true
                    handlesNumericalFeatures = $true
                    handlesCategoricalFeatures = $true
                    includesCustomTransformer = $true
                    demonstratesFitTransform = $true
                } `
                -RequiredEvidence @(
                    @{ source = "sklearn"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("usesPipeline", "usesColumnTransformer", "handlesNumericalFeatures")
                    forbiddenPatterns = @()
                    minConfidence = 0.85
                } `
                -Tags @("notebook", "feature-engineering", "sklearn", "pipeline", "ml")
            ),

            # Task 9: Model Training Tracking
            (New-GoldenTask `
                -TaskId "gt-notebook-data-009" `
                -Name "Model training tracking" `
                -Description "Track ML experiments and model training metrics" `
                -PackId "notebook-data" `
                -Category "integration" `
                -Difficulty "medium" `
                -Query "Implement experiment tracking in a Jupyter notebook using MLflow, wandb, or tensorboard to log parameters, metrics, artifacts, and model versions." `
                -ExpectedResult @{
                    logsParameters = $true
                    logsMetrics = $true
                    logsArtifacts = $true
                    tracksModelVersions = $true
                    providesExperimentComparison = $true
                } `
                -RequiredEvidence @(
                    @{ source = "mlflow"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("logsParameters", "logsMetrics", "tracksModelVersions")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("notebook", "mlflow", "experiment-tracking", "ml", "logging")
            ),

            # Task 10: Experiment Comparison
            (New-GoldenTask `
                -TaskId "gt-notebook-data-010" `
                -Name "Experiment comparison" `
                -Description "Compare multiple ML experiments and generate comparison reports" `
                -PackId "notebook-data" `
                -Category "comparison" `
                -Difficulty "medium" `
                -Query "Write code to compare multiple ML experiment runs, generating visual comparisons of metrics, parameter diffs, and ranking models by performance criteria." `
                -ExpectedResult @{
                    comparesMultipleRuns = $true
                    visualizesMetricComparison = $true
                    showsParameterDiffs = $true
                    ranksModels = $true
                    generatesComparisonReport = $true
                } `
                -RequiredEvidence @(
                    @{ source = "experiment-comparison"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("comparesMultipleRuns", "visualizesMetricComparison", "generatesComparisonReport")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("notebook", "experiment-comparison", "ml", "visualization", "benchmark")
            )
        )

        #=======================================================================
        # Agent Simulation Pack Golden Tasks (10 tasks)
        #=======================================================================
        $agentSimTasks = @(
            # Task 1: Multi-Agent Setup
            (New-GoldenTask `
                -TaskId "gt-agent-sim-001" `
                -Name "Multi-agent setup" `
                -Description "Configure and initialize a multi-agent simulation environment" `
                -PackId "agent-sim" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Create a multi-agent simulation setup using Python with agent definitions, environment state, agent communication channels, and coordination mechanisms." `
                -ExpectedResult @{
                    definesAgentClass = $true
                    initializesMultipleAgents = $true
                    setsUpCommunication = $true
                    definesEnvironmentState = $true
                    implementsCoordination = $true
                } `
                -RequiredEvidence @(
                    @{ source = "multi-agent"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("definesAgentClass", "initializesMultipleAgents", "setsUpCommunication")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("agent", "multi-agent", "simulation", "coordination", "mas")
            ),

            # Task 2: Reward Function Design
            (New-GoldenTask `
                -TaskId "gt-agent-sim-002" `
                -Name "Reward function design" `
                -Description "Design and implement reward functions for reinforcement learning agents" `
                -PackId "agent-sim" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Design a reward function for an RL agent including sparse vs dense rewards, shaping techniques, multi-objective weighting, and penalty structures." `
                -ExpectedResult @{
                    implementsSparseReward = $true
                    implementsDenseReward = $true
                    includesRewardShaping = $true
                    handlesMultiObjective = $true
                    definesPenaltyStructure = $true
                } `
                -RequiredEvidence @(
                    @{ source = "rl-rewards"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("implementsDenseReward", "includesRewardShaping", "definesPenaltyStructure")
                    forbiddenPatterns = @()
                    minConfidence = 0.85
                } `
                -Tags @("agent", "rl", "reward-function", "reinforcement-learning", "shaping")
            ),

            # Task 3: Trajectory Analysis
            (New-GoldenTask `
                -TaskId "gt-agent-sim-003" `
                -Name "Trajectory analysis" `
                -Description "Analyze agent behavior trajectories and state transitions" `
                -PackId "agent-sim" `
                -Category "analysis" `
                -Difficulty "medium" `
                -Query "Write code to analyze agent trajectories including state-action sequences, path optimization, divergence detection, and trajectory clustering." `
                -ExpectedResult @{
                    analyzesStateActionSequences = $true
                    detectsPathPatterns = $true
                    identifiesDivergences = $true
                    clustersTrajectories = $true
                    calculatesPathMetrics = $true
                } `
                -RequiredEvidence @(
                    @{ source = "trajectory-analysis"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("analyzesStateActionSequences", "identifiesDivergences", "clustersTrajectories")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("agent", "trajectory", "analysis", "behavior", "paths")
            ),

            # Task 4: A/B Testing Framework
            (New-GoldenTask `
                -TaskId "gt-agent-sim-004" `
                -Name "A/B testing framework" `
                -Description "Implement A/B testing for comparing agent policies or behaviors" `
                -PackId "agent-sim" `
                -Category "integration" `
                -Difficulty "medium" `
                -Query "Create an A/B testing framework for agent policies including random assignment, statistical significance testing, confidence intervals, and performance comparison." `
                -ExpectedResult @{
                    implementsRandomAssignment = $true
                    calculatesStatisticalSignificance = $true
                    computesConfidenceIntervals = $true
                    comparesPolicies = $true
                    handlesSampleSizeCalculation = $true
                } `
                -RequiredEvidence @(
                    @{ source = "ab-testing"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("implementsRandomAssignment", "calculatesStatisticalSignificance", "comparesPolicies")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("agent", "ab-testing", "statistics", "policy-comparison", "experiment")
            ),

            # Task 5: Environment Configuration
            (New-GoldenTask `
                -TaskId "gt-agent-sim-005" `
                -Name "Environment configuration" `
                -Description "Configure simulation environments with Gymnasium/PettingZoo" `
                -PackId "agent-sim" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Create a custom Gymnasium environment with proper observation/action spaces, reset/step methods, rendering, and environment registration." `
                -ExpectedResult @{
                    extendsGymEnv = $true
                    definesObservationSpace = $true
                    definesActionSpace = $true
                    implementsReset = $true
                    implementsStep = $true
                    registersEnvironment = $true
                } `
                -RequiredEvidence @(
                    @{ source = "gymnasium"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("extendsGymEnv", "implementsReset", "implementsStep")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("agent", "gymnasium", "environment", "rl", "simulation")
            ),

            # Task 6: Agent Behavior Validation
            (New-GoldenTask `
                -TaskId "gt-agent-sim-006" `
                -Name "Agent behavior validation" `
                -Description "Validate agent behaviors against expected policies and constraints" `
                -PackId "agent-sim" `
                -Category "validation" `
                -Difficulty "medium" `
                -Query "Implement validation tests for agent behaviors including policy conformance checking, safety constraint validation, and behavioral invariants." `
                -ExpectedResult @{
                    validatesPolicyConformance = $true
                    checksSafetyConstraints = $true
                    verifiesBehavioralInvariants = $true
                    testsEdgeCases = $true
                    providesValidationReport = $true
                } `
                -RequiredEvidence @(
                    @{ source = "behavior-validation"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("validatesPolicyConformance", "checksSafetyConstraints", "providesValidationReport")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("agent", "validation", "behavior", "safety", "testing")
            ),

            # Task 7: Policy Optimization
            (New-GoldenTask `
                -TaskId "gt-agent-sim-007" `
                -Name "Policy optimization" `
                -Description "Implement policy gradient and optimization algorithms" `
                -PackId "agent-sim" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Implement a policy gradient algorithm (REINFORCE, PPO, or A2C) with neural network policy, value function, and training loop." `
                -ExpectedResult @{
                    implementsPolicyNetwork = $true
                    implementsValueFunction = $true
                    calculatesPolicyGradient = $true
                    includesTrainingLoop = $true
                    handlesAdvantageEstimation = $true
                } `
                -RequiredEvidence @(
                    @{ source = "policy-gradient"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("implementsPolicyNetwork", "calculatesPolicyGradient", "includesTrainingLoop")
                    forbiddenPatterns = @()
                    minConfidence = 0.85
                } `
                -Tags @("agent", "policy-gradient", "ppo", "reinforcement-learning", "optimization")
            ),

            # Task 8: Simulation Replay
            (New-GoldenTask `
                -TaskId "gt-agent-sim-008" `
                -Name "Simulation replay" `
                -Description "Record and replay simulation episodes for debugging and analysis" `
                -PackId "agent-sim" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Create a simulation replay system that records episodes (states, actions, rewards) and supports playback, stepping, and event inspection." `
                -ExpectedResult @{
                    recordsEpisodeData = $true
                    supportsPlayback = $true
                    allowsStepping = $true
                    inspectsEvents = $true
                    savesReplayFiles = $true
                } `
                -RequiredEvidence @(
                    @{ source = "simulation-replay"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("recordsEpisodeData", "supportsPlayback", "allowsStepping")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("agent", "replay", "simulation", "debugging", "recording")
            ),

            # Task 9: Metrics Collection
            (New-GoldenTask `
                -TaskId "gt-agent-sim-009" `
                -Name "Metrics collection" `
                -Description "Collect and aggregate agent performance metrics" `
                -PackId "agent-sim" `
                -Category "integration" `
                -Difficulty "easy" `
                -Query "Implement a metrics collection system for agents including episode rewards, success rates, convergence tracking, and custom metric aggregation." `
                -ExpectedResult @{
                    tracksEpisodeRewards = $true
                    calculatesSuccessRates = $true
                    monitorsConvergence = $true
                    aggregatesStatistics = $true
                    exportsMetricsData = $true
                } `
                -RequiredEvidence @(
                    @{ source = "metrics"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("tracksEpisodeRewards", "calculatesSuccessRates", "monitorsConvergence")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("agent", "metrics", "performance", "monitoring", "statistics")
            ),

            # Task 10: Agent Collaboration Patterns
            (New-GoldenTask `
                -TaskId "gt-agent-sim-010" `
                -Name "Agent collaboration patterns" `
                -Description "Implement collaboration patterns for multi-agent systems" `
                -PackId "agent-sim" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Implement agent collaboration patterns including auction-based allocation, consensus algorithms, shared memory, and emergent coordination strategies." `
                -ExpectedResult @{
                    implementsAuctionMechanism = $true
                    implementsConsensus = $true
                    usesSharedMemory = $true
                    demonstratesEmergentCoordination = $true
                    handlesCommunicationOverhead = $true
                } `
                -RequiredEvidence @(
                    @{ source = "collaboration"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("implementsAuctionMechanism", "implementsConsensus", "demonstratesEmergentCoordination")
                    forbiddenPatterns = @()
                    minConfidence = 0.85
                } `
                -Tags @("agent", "collaboration", "multi-agent", "coordination", "distributed")
            )
        )

        # Combine all tasks
        $allTasks = $rpgmakerTasks + $godotTasks + $blenderTasks + $apiReverseTasks + $notebookDataTasks + $agentSimTasks

        # Filter by pack if specified
        if ($PackId) {
            return $allTasks | Where-Object { $_.packId -eq $PackId }
        }

        return $allTasks
    }
}
