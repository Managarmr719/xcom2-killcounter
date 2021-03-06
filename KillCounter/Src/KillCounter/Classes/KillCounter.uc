class KillCounter extends UIScreenListener implements(X2VisualizationMgrObserverInterface);

var int LastRealizedIndex;
var array<int> AlreadySeenIndexes;

event OnInit(UIScreen Screen)
{	
	// For some unknown reason LastRealizedIndex can't be just set to
	// `defaults.LastRealizedIndex`; I assume the default value got somehow
	// overwritten during the reinit of screens. Having -1 hardcoded solves
	// any "the UI doesn't update" issues I have seen so far.
	LastRealizedIndex = -1;
	AlreadySeenIndexes.Length = 0;

	class'KillCounter_Utils'.static.GetUI();
	RegisterEvents();

	// A call to GetUI will initialize the UI if it isn't already. This
	// fixes a bug where the UI isn't shown after a savegame load in tactical.
	class'KillCounter_Utils'.static.GetUI();
}

event OnRemoved(UIScreen Screen)
{
	UnregisterEvents();
	DestroyUI();
}

event OnVisualizationBlockComplete(XComGameState AssociatedGameState)
{
	if(!AssociatedGameState.bIsDelta)
	{
		// The first given GameState is always a full one (what makes sense).
		// That state has the id 0. The next state will be 1 if it's a new
		// mission, which is also fine and expected. But the code below can't
		// deal with the skip a load does. When loaded, the game will fast
		// forward the already played GameStates and will send us an update
		// with the next new GameState, missing out hundreds of GameStates we
		// would normally expect to see. To cope with this, we just ignore the
		// full GameState and start with the first detla state we get.
		return;
	}

	if(ShouldGivenGameStateBeUsed(AssociatedGameState.HistoryIndex))
	{
		UpdateUI(AssociatedGameState.HistoryIndex);
	}
}

function int sortIntArrayAsc(int a, int b)
{
	return b - a;
}

// This function revolves arround two things:
//
//  0) The game seems to guarantee that no index id will be skipped. It's build
//     arround this assumpion. If something breaks that assumption, this will
//     softlock (read: never update again) immediatly.
//  1) While 0) is true, the game does not guarantee that these indexes come in
//     ascending order. In fact they come scattered in groups, skipping parts
//     here and there as the visualization unfolds. This function has to make
//     sure that it only progresses the UI state when the visualization
//     belonging to that UI state has been completed.
//  2) As certain events might cause other events (a move might reveal a pod),
//     the Game has the concept of 'interrupted frames'. Whenever a Frame is
//     interrupted (indicated in the GameStateContext), this GameState will
//     never be visualized and therefor will never end up here. This function
//     has to carefully manouver around skipped frames and already seen frames
//     therefor.
function bool ShouldGivenGameStateBeUsed(int index)
{
	local int startPos, endPos;
	local int startIndex;
	local int interrupted;

	local KillCounter_Settings settings;
	local bool debug;
	local string logStr;
	
	// The performance penalty hopefully isn't that bad. I assume computing all
	// the log strings does have a bigger impact than checking for the debug
	// flag (and creating an instance before).
	settings = new class'KillCounter_Settings';
	debug = settings.IsDebugEnabled();

	if(debug)
	{
		`log("Index: " @ string(index) @ "LastRealizedIndex: "  @ string(LastRealizedIndex));
	}

	// Short circuit: If it's the next frame we would expect, just roll with
	// it. Same if this is the first index we do see in this play session.
	if(index == LastRealizedIndex + 1 || LastRealizedIndex == -1)
	{
		LastRealizedIndex = index;
		if(debug)
		{
			`log("Ret: True (1)");
		}
		return true;
	}

	// As there might (and will be) interrupted frames between the
	// LastRealizedIndex and the given index, we need to pick the next index
	// AFTER the LastRealizedIndex which is not an interrupted frame to base
	// our calculations on.
	startIndex = findFirstNonInterruptedFrame(LastRealizedIndex + 1);

	// Special Case: There is no frame in the future which is considered
	// uninterrupted. In this case the firstNonInterruptedFrame is the
	// LastRealizedIndex per definition.
	if(startIndex == -1)
	{
		startIndex = LastRealizedIndex;
	}

	// Special Case: The frame(s) we didn't saw will never come as they were
	// interrupted. This saves us from doing the definately more expensive
	// Code further down.
	if(startIndex == index)
	{
		LastRealizedIndex = index;
		if(debug)
		{
			`log("Reg: True (2)");
		}
		return true;
	}

	// Add the given index now in any case to the array we have of 'frames we
	// have seen but we can't use by now'. Also we keep this array sorted in
	// ascending order at all times to keep the code here simpler.
	AlreadySeenIndexes.AddItem(index);
	AlreadySeenIndexes.Sort(sortIntArrayAsc);

	// Try to locate both the first non interrupted frame and the given index.
	// If any of them couldn't be found, we can immediatly return here.
	startPos = AlreadySeenIndexes.Find(startIndex);
	endPos = AlreadySeenIndexes.Find(index);

	if(debug)
	{
		`log("startIndex: " @ startIndex);
		`log("startPos: " @ startPos @ " endPos: " @ endPos);
	}

	if (startPos == INDEX_NONE || endPos == INDEX_NONE)
	{
		if(debug)
		{
			`log("Ret: False (3)");
		}
		return false;
	}

	// To calculate if we do have already seen all the frames we were missing
	// in the past we do have to find out how many frames between startIndex
	// and index were interrupted (and therefore will never show up in our
	// list).
	interrupted = findInterruptCountBetween(startIndex, index);
	if(debug)
	{
		`log("Interrupted between " @ string(startIndex) @ " and " @ string(index) @ ":" @ string(interrupted));
	}

	// Now to the actual checking: All we check here is if the sum of the
	// indexes we have gathered in our array PLUS all the interrupted frames
	// do match up with the number of frames between the first non interrupted
	// frame after our LastRealizedFrame (this is the startIndex) and the 
	// given index. Simple, isn't it? *cough*
	if(debug)
	{
		`log("A: " @ string((endPos - startPos + interrupted)) @ " B: " @ string((index - startIndex)));
	}

	// Normally I wouldn't want to have a >= here but a ==. But it turned out
	// that there is a case where an unexpected frame turned up in the list
	// even though it wasn't expected. Having a >= doesn't hurt as long as the
	// rest of the calculation is correct as 'too much' isn't really a big deal,
	// we do need to have 'at least' (index - startIndex) frames. Hopefully
	// this code is now a little more robust thanks to that laxing in
	// requirements.
	if ((endPos - startPos + interrupted) >= (index - startIndex))
	{
		// If so, remove all of the now no longer needed indexes from the
		// array and move on.
		AlreadySeenIndexes.Remove(startPos, endPos - startPos + 1);
		LastRealizedIndex = index;
		if(debug)
		{
			`log("Ret: True (4)");
		}
		return true;
	}

	if(debug)
	{
		logStr = "Indexes:";
		ForEach AlreadySeenIndexes(startIndex)
		{
			logStr @= startIndex;
		}
		`log(logStr);
		`log("Ret: False (5)");
	}
	return false;
}

function int findFirstNonInterruptedFrame(int start)
{
	local int frame;
	for(frame = start; frame <= `XCOMHISTORY.GetCurrentHistoryIndex(); frame++)
	{
		if(!class'KillCounter_Utils'.static.IsGameStateInterrupted(frame))
		{
			return frame;
		}
	}
	
	return -1;
}

function int findInterruptCountBetween(int start, int end)
{
	local int interrupted, i;

	interrupted = 0;
	for(i = start + 1; i < end; i++)
	{
		if(class'KillCounter_Utils'.static.IsGameStateInterrupted(i))
		{
			interrupted++;
		}
	}

	return interrupted;
}

event OnVisualizationIdle()
{
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

function DestroyUI()
{
	local KillCounter_UI ui;
	ui = class'KillCounter_Utils'.static.GetUI();
	if(ui == none)
	{
		return;
	}

	ui.Remove();
}

function UpdateUI(int historyIndex)
{
	local KillCounter_UI ui;
	ui = class'KillCounter_Utils'.static.GetUI(); 
	if(ui == none)
	{
		return;
	}

	ui.Update(historyIndex);
}

defaultproperties
{
	ScreenClass = class'UITacticalHUD';
	LastRealizedIndex = -1;
}