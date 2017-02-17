class KillCounter extends UIScreenListener implements(X2VisualizationMgrObserverInterface) config(KillCounter);

var config bool neverShowEnemyTotal;
var config bool neverShowActiveEnemyCount;
var config bool alwaysShowEnemyTotal;
var config bool showRemainingInsteadOfTotal;
var config bool includeTurrets;
var config bool onlyShowInitialEnemyTotal;

var bool ShowTotal;
var bool ShowActive;
var bool ShowRemaining;
var bool ShowInitialTotal;
var bool SkipTurrets;

var int LastRealizedIndex;

event OnInit(UIScreen Screen)
{
	ShowTotal = ShouldDrawTotalCount();
	ShowActive = ShouldDrawActiveCount();
	ShowRemaining = ShouldDrawRemainingCount();
	ShowInitialTotal = ShouldShowInitialTotal();
	SkipTurrets = ShouldSkipTurrets();

	RegisterEvents();
}

event OnRemoved(UIScreen Screen)
{
	UnregisterEvents();
	DestroyUI();
}

event OnVisualizationBlockComplete(XComGameState AssociatedGameState)
{
	if( AssociatedGameState.HistoryIndex == `XCOMHISTORY.GetCurrentHistoryIndex() )
	{
		UpdateUI();
	}
}

event OnVisualizationIdle();

event OnActiveUnitChanged(XComGameState_Unit NewActiveUnit);

function EventListenerReturn OnReEvaluationEvent(Object EventData, Object EventSource, XComGameState GameState, Name EventID)
{
	if( GameState.HistoryIndex != LastRealizedIndex )
	{
		UpdateUI();
	}

	return ELR_NoInterrupt;
}

function RegisterEvents()
{
	local X2EventManager EventManager;
	local Object ThisObj;

	`XCOMVISUALIZATIONMGR.RegisterObserver(self);

	EventManager = `XEVENTMGR;
	ThisObj = self;
	EventManager.RegisterForEvent(ThisObj, 'AbilityActivated', OnReEvaluationEvent, ELD_OnVisualizationBlockStarted);
	EventManager.RegisterForEvent(ThisObj, 'ScamperBegin', OnReEvaluationEvent, ELD_OnVisualizationBlockStarted);
	EventManager.RegisterForEvent(ThisObj, 'UnitDied', OnReEvaluationEvent, ELD_OnVisualizationBlockStarted);
}

function UnregisterEvents()
{
	local X2EventManager EventManager;
	local Object ThisObj;

	`XCOMVISUALIZATIONMGR.RemoveObserver(self);

	EventManager = `XEVENTMGR;
	ThisObj = self;
	EventManager.UnRegisterFromAllEvents(ThisObj);
}

function KillCounter_UI GetUI()
{
	local UIScreen hud;
	local KillCounter_UI ui;

	hud = `PRES.GetTacticalHUD();
	if (hud == none)
	{
		return none;
	}

	ui = KillCounter_UI(hud.GetChild('KillCounter_UI'));

	if(ui == none)
	{
		ui = hud.Spawn(class'KillCounter_UI', hud);
		ui.InitPanel('KillCounter_UI');
	}

	return ui;
}

function DestroyUI()
{
	local KillCounter_UI ui;
	ui = GetUI();
	if(ui == none)
	{
		return;
	}

	ui.Remove();
}

function UpdateUI()
{
	local int killed, total, active, initial;
	local KillCounter_UI ui;
	
	ui = GetUI(); 
	if(ui == none)
	{
		return;
	}

	killed = class'KillCounter_Utils'.static.GetKilledEnemies(SkipTurrets);
	active = ShowActive ? class'KillCounter_Utils'.static.GetActiveEnemies(SkipTurrets) : -1;
	total = ShowTotal ? class'KillCounter_Utils'.static.GetTotalEnemies(SkipTurrets) : -1;
	initial = ShowInitialTotal ? class'KillCounter_Utils'.static.GetInitialEnemyCount(SkipTurrets) : -1;

	if(initial == 0 && !)
	{
	}

	ui.UpdateText(killed, total, active, initial, ShowRemaining);

	LastRealizedIndex = `XCOMHISTORY.GetCurrentHistoryIndex();
}

function bool ShouldDrawTotalCount()
{
	if(alwaysShowEnemyTotal)
	{
		return true;
	}
	else if(neverShowEnemyTotal) 
	{
		return false;
	} 

	return class'KillCounter_Utils'.static.IsShadowChamberBuild();
}

function bool ShouldDrawActiveCount()
{
	return !neverShowActiveEnemyCount;
}

function bool ShouldDrawRemainingCount()
{
	return showRemainingInsteadOfTotal;
}

function bool ShouldSkipTurrets()
{
	return !includeTurrets;
}

function bool ShouldShowInitialTotal()
{
	return onlyShowInitialEnemyTotal;
}

defaultproperties
{
	ScreenClass = class'UITacticalHUD';
	ShowTotal = false;
	ShowActive = true;
	ShowRemaining = true;
	SkipTurrets = true;
}