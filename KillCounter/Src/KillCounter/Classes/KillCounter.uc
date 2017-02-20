class KillCounter extends UIScreenListener implements(X2VisualizationMgrObserverInterface) config(KillCounter);

var config bool neverShowEnemyTotal;
var config bool neverShowActiveEnemyCount;
var config bool alwaysShowEnemyTotal;
var config bool showRemainingInsteadOfTotal;
var config bool includeTurrets;

var bool ShowTotal;
var bool ShowActive;
var bool ShowRemaining;
var bool SkipTurrets;

var int LastKilled;
var int LastActive;
var int LastTotal;

var int LastRealizedIndex;
var array<int> AlreadySeenIndexes;
var bool FirstTime;

event OnInit(UIScreen Screen)
{
	ShowTotal = ShouldDrawTotalCount();
	ShowActive = ShouldDrawActiveCount();
	ShowRemaining = ShouldDrawRemainingCount();
	SkipTurrets = ShouldSkipTurrets();

	// Reset is needed here for a load from Tactical to Tactical
	LastKilled = -1;
	LastActive = -1;
	LastTotal = -1;
	FirstTime = true;
	LastRealizedIndex = -1;
	AlreadySeenIndexes.Length = 0;

	RegisterEvents();
}

event OnRemoved(UIScreen Screen)
{
	UnregisterEvents();
	DestroyUI();
}

event OnVisualizationBlockComplete(XComGameState AssociatedGameState)
{
	if(FirstTime)
	{
		`log("First Trigger skipped!");
		FirstTime = false;
		return;
	}

	if(!ShouldGivenGameStateBeUsed(AssociatedGameState.HistoryIndex))
	{
		return;
	}

	UpdateUI(AssociatedGameState.HistoryIndex);
}

function int sortIntArrayAsc(int a, int b)
{
	return b - a;
}

function bool ShouldGivenGameStateBeUsed(int index)
{
	local int startPos, endPos;
	local int startIndex;
	local int interrupted;
	local int logIndex;
	local string logStr;

	`log("Index: " @ string(index) @ "LastRealizedIndex: " @ string(LastRealizedIndex));
	if(index == LastRealizedIndex + 1 || LastRealizedIndex == -1)
	{
		LastRealizedIndex = index;
		`log("Ret: True (1)");
		return true;
	}

	startIndex = findFirstNonInterruptedFrame(LastRealizedIndex + 1);

	// Special Case: The frame(s) we didn't saw will never come as they were interrupted
	if(startIndex == index)
	{
		LastRealizedIndex = index;
		`log("Reg: True (2)");
		return true;
	}

	AlreadySeenIndexes.AddItem(index);
	AlreadySeenIndexes.Sort(sortIntArrayAsc);

	startPos = AlreadySeenIndexes.Find(startIndex);
	endPos = AlreadySeenIndexes.Find(index);

	`log("startIndex: " @ startIndex);
	`log("startPos: " @ startPos @ " endPos: " @ endPos);
	if (startPos == INDEX_NONE || endPos == INDEX_NONE)
	{
		`log("Ret: False (3)");
		return false;
	}

	interrupted = findInterruptCountBetween(startIndex, index);
	`log("Interrupted between " @ string(startIndex) @ " and " @ string(index) @ ":" @ string(interrupted));

	`log("A: " @ string((endPos - startPos + interrupted)) @ " B: " @ string((index - startIndex)));
	if ((endPos - startPos + interrupted) == (index - startIndex))
	{
		logStr = "Pre remove:";
		ForEach AlreadySeenIndexes(logIndex)
		{
			logStr @= string(logIndex);
		}
		`log(logStr);

		AlreadySeenIndexes.Remove(startPos, endPos - startPos + 1);
		LastRealizedIndex = index;

		logstr = "Post remove:";
		ForEach AlreadySeenIndexes(logIndex)
		{
			logStr @= string(logIndex);
		}
		`log(logStr);
		`log("Ret: True (4)");
		return true;
	}

	`log("Ret: False (5)");
	return false;
}

function int findFirstNonInterruptedFrame(int start)
{
	local int frame;
	for(frame = start; frame > 0; frame++)
	{
		if(!IsGameStateInterrupted(frame))
		{
			return frame;
		}
	}
}

function int findInterruptCountBetween(int start, int end)
{
	local int interrupted, i;

	interrupted = 0;
	for(i = start; i < end; i++)
	{
		if(IsGameStateInterrupted(i))
		{
			interrupted++;
		}
	}

	return interrupted;
}

function bool IsGameStateInterrupted(int index)
{
	local XComGameState gameState;
	local XComGameStateContext context;

	gameState = `XCOMHISTORY.GetGameStateFromHistory(index);
	if(gameState == none)
	{
		return true;
	}

	context = gameState.GetContext();
	if(context == none)
	{
		return true;
	}

	return context.InterruptionStatus == eInterruptionStatus_Interrupt;
}

event OnVisualizationIdle()
{
	local XComGameState gameState;
	local int startIndex, endIndex, cur;

	`log("XXXX History Dump");
	startIndex = `XCOMHISTORY.GetCurrentHistoryIndex();
	for(cur = startIndex; cur > startIndex - 100 && cur > 0; cur--)
	{
		gameState = `XCOMHISTORY.GetGameStateFromHistory(cur);
		`log(cur @ gameState.GetContext().SummaryString());
	}

	if(AlreadySeenIndexes.Length == 0)
	{
		return;
	}

	`log("XXXX AlreadySeen Debug Dump");
	startIndex = LastRealizedIndex + 1;
	endIndex = AlreadySeenIndexes[AlreadySeenIndexes.Length - 1];
	for(cur = startIndex; cur <= endIndex; cur++)
	{
		gameState = `XCOMHISTORY.GetGameStateFromHistory(cur);
		if(AlreadySeenIndexes.Find(cur) == INDEX_NONE && !IsGameStateInterrupted(cur))
		{
			`log(cur @ gameState.GetContext().SummaryString());
		}
	}
}

event OnActiveUnitChanged(XComGameState_Unit NewActiveUnit);

function RegisterEvents()
{
	`XCOMVISUALIZATIONMGR.RegisterObserver(self);
}

function UnregisterEvents()
{
	`XCOMVISUALIZATIONMGR.RemoveObserver(self);
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

function UpdateUI(int historyIndex)
{
	local int killed, total, active;
	local KillCounter_UI ui;
	
	ui = GetUI(); 
	if(ui == none)
	{
		return;
	}

	killed = class'KillCounter_Utils'.static.GetKilledEnemies(historyIndex, SkipTurrets);
	active = ShowActive ? class'KillCounter_Utils'.static.GetActiveEnemies(historyIndex, SkipTurrets) : -1;
	total = ShowTotal ? class'KillCounter_Utils'.static.GetTotalEnemies(SkipTurrets) : -1;

	if (killed != LastKilled || active != LastActive || total != LastTotal)
	{
		ui.UpdateText(killed, total, active, ShowRemaining);
		
		LastKilled = killed;
		LastActive = active;
		LastTotal = total;

		`log("Killed:" @ killed @ "Active:" @ active @ "Total:" @ total); 
	}
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

defaultproperties
{
	ScreenClass = class'UITacticalHUD';
	ShowTotal = false;
	ShowActive = true;
	ShowRemaining = true;
	SkipTurrets = true;
	LastKilled = -1;
	LastActive = -1;
	LastTotal = -1;
	LastRealizedIndex = -1;
	FirstTime = true;
}