import QtQuick 2.2;
import QtQuick.Controls 2.2;
import MuseScore 3.0

MuseScore
{
    id: odla;
    version: "1.7.5";
    description: qsTr("This plugin allows the use of the ODLA keyboard in the Musescore program");
    title: "ODLA";
    categoryCode: "composing-arranging-tools"
    thumbnailName: "ODLA.png";
    requiresScore: false;

    property var cursor: null;
    property var socket: null;
    property var lastScore: null;
    property int lastVoice: 0;
    property bool noteInput: false;

    property int connectedToServerSocketId: -1;
    property int clientSocketId: -1;

    readonly property int barline_NORMAL            : 1 << 0;
    readonly property int barline_DOUBLE            : 1 << 1;
    readonly property int barline_REPEAT_START      : 1 << 2;
    readonly property int barline_REPEAT_STOP       : 1 << 3;
    readonly property int barline_DASHED            : 1 << 4;
    readonly property int barline_FINAL             : 1 << 5;
    readonly property int barline_REPEAT_START_STOP : 1 << 6;
    readonly property int barline_DOTTED            : 1 << 7;

    Timer
    {
        id: newScoreOpenedTimer;
        interval: 1000;
        running: true;
        repeat: true;

        onTriggered:
        {
            // If score has changed (even if from null)
            if(newScoreOpened())
            {
                cursor = curScore.newCursor();
                cursor.inputStateMode=Cursor.INPUT_STATE_SYNC_WITH_SCORE;
                setNoteInputMode(true);
            }
        }
    }

    function newScoreOpened()
    {
        let changed = false;
        if(lastScore === null && curScore !== null)
        {
            debug("Score opened");
            changed = true;
        }
        else if(lastScore !== null && curScore !== null && !lastScore.is(curScore))
        {
            debug("Score changed");
            changed = true;
        }
        lastScore = curScore;
        return changed;
    }

    onRun:
    {
        debug("ODLA plugin is running on Musescore version " + mscoreVersion);

        // Prova a connetterti al segnale di chiusura dell'app
        if (Qt.application && Qt.application.aboutToQuit)
            Qt.application.aboutToQuit.connect(sendShuttingDown);

        // first articulation loading is slow, so we load it now
        newScoreOpenedTimer.start();

        api.websocketserver.listen(6433, function(id)
        {
            debug("ODLA Server in listening from client: " + id);
            if (odla.connectedToServerSocketId === -1)
            {
                odla.connectedToServerSocketId = id;
                api.websocketserver.onMessage(odla.connectedToServerSocketId, odla.onMessageReceived)
            }
        });
    }

    function onMessageReceived(msg)
    {
        debug("Received message: " + msg);
        let odlaCommand = JSON.parse(msg);
        const fn = odlaCommand.functionName;

        if (curScore !== null)
        {
            if ('SpeechFlags' in odlaCommand)
            {
                debug("Creating and sending speech message");
                const message = createSpeechMessage(odlaCommand.SpeechFlags);
                api.websocketserver.send(odla.connectedToServerSocketId, message);
            }

            if ('note_entry' in odlaCommand)
            {
                debug("Executing setNoteInputMode");
                setNoteInputMode(odlaCommand.note_entry);
            }

            if (fn === "quit")
            {
                debug("Forced shortcut execution: quit");
                executeShortcut("quit");
                return;
            }

            if (typeof odla[fn] === "function")
            {
                debug("Executing function: " + fn);
                odla[fn](odlaCommand);
                return;
            }
        }

        if (fn && typeof odla[fn] !== "function")
        {
            debug("Executing shortcut: " + fn);
            executeShortcut(fn);
        }
    }

    function setBarline(p)
    {
        let prevTick = cursor.tick;
        cursor.filter = Segment.BarLineType;
        if(p.value === barline_REPEAT_START)
        {
            cursor.prev();
            cursor.prev();
        }
        else
            cursor.next();

        if(cursor.element !== "undefined" && cursor.element !== null)
        {
            curScore.startCmd();
            cursor.element.barlineType = p.value;
            curScore.endCmd();
        }
        cursor.filter = Segment.ChordRest;
        cursor.next();
        cursor.prev();

        setNoteInputMode(false);
        setNoteInputMode(true);
    }

    function selectMeasures(p)
    {
        var firstMeasure = getMeasure(p.firstMeasure);
        var lastMeasure = getMeasure(p.lastMeasure);
        let startTick = firstMeasure.firstSegment.tick;
        let endTick = lastMeasure.lastSegment.tick;
        curScore.startCmd();
        curScore.selection.selectRange(startTick, endTick+1, 0, curScore.nstaves)
        curScore.endCmd();
    }

    function addDynamic(p)
    {
        let dyn = newElement(Element.DYNAMIC);
        dyn.subtype = p.subtype;
        dyn.text = p.text;
        curScore.startCmd();
        cursor.add(dyn);
        curScore.endCmd();
    }

    function addTimeSignature(p)
    {
        let currentNoteInput = noteInput;
        let currentTrack = cursor.track;
        let ts=newElement(Element.TIMESIG);
        ts.timesig=fraction(p.numerator, p.denominator);
        cursor.track = 0;
        curScore.startCmd();
        cursor.add(ts);
        curScore.endCmd();
        cursor.track = currentTrack;
        setNoteInputMode(currentNoteInput);
        setNoteInputMode(currentNoteInput);
        // ms4 crashes if add timesig in piano left hand track
        // so we have some bad code to compensate the problem
        // TODO: common time and alla breve
    }

    function staffPressed(p)
    {
        if(!isCursorInTablature())
            addNoteToScore(p.odlaKey, p.chord);
        else
            selectStringFromOdlaKey(p.odlaKey);
    }

    function insertMeasures(p)
    {
        debug("inserting: " + p.value + " measures")
        for(let i = 0; i < p.value; i++)
            cmd("insert-measure")
    }

    function addTempo(p)
    {
        let t = newElement(Element.TEMPO_TEXT);
        t.followText = 1; // va aggiornato ?
        t.text = p.text;
        t.tempo = parseFloat(p.tempo / p.time_divider);
        curScore.startCmd();
        cursor.add(t);
        curScore.endCmd();
    }

    function goTo(p)
    {
        let currentMeasureNumber = getElementMeasureNumber(cursor.element);
        let firstMeasure = curScore.firstMeasure;
        let lastMeasure = curScore.lastMeasure;

        if(p.value === -1)
            p.value = getElementMeasureNumber(lastMeasure);

        while(currentMeasureNumber !== p.value)
        {
            let currentSelectedMeasure = getParentOfType(cursor.element, "Measure");
            if(currentMeasureNumber > p.value && !currentSelectedMeasure.is(firstMeasure))
            {
                cmd("notation-move-left-quickly");
                currentMeasureNumber--;
            }
            else if(currentMeasureNumber < p.value && !currentSelectedMeasure.is(lastMeasure))
            {
                cmd("notation-move-right-quickly");
                currentMeasureNumber++;
            }
            else
                break;
        }
    }

    function toggleNoteInputMode(p)
    {
        debug(p);
        setNoteInputMode(!noteInput);
    }

    // Bad way (wait for better API) to ensure note input
    function setNoteInputMode(status)
    {
        if(status === true && (noteInput === false || curScore.selection.elements.length === 0))
        {
            if(mscoreVersion >= 40500)
                cmd("note-input-by-note-name");
            else
                cmd("note-input-steptime");
            noteInput = true;
        }
        else if(status === false && noteInput === true)
        {
            cmd("notation-escape");
            noteInput = false;
        }
    }

    function isCursorInPitchedStaff()
    {
        try {
            return curScore.staves[cursor.staffIdx].part.hasPitchedStaff;
        } catch (error) {
            return false;
        }
    }

    function isCursorInTablature()
    {
        try {
            return curScore.staves[cursor.staffIdx].part.hasTabStaff;
        } catch (error) {
            return false;
        }
    }

    /*
     * getNotePitch (Element) -> int
     * Get note pitch of Element or -1 if it's a pause
     */
    function getNotePitch(element)
    {
        if(element.type === Element.NOTE)
            return element.pitch;
        if(element.type === Element.CHORD)
            return element.notes[0].pitch;
        else if(element.type === Element.REST)
            return -1;
        else
            return -2;
    }

    function getElementStaff(element)
    {
        for(let i = 0; i < curScore.nstaves; i++)
            if(element.staff.is(curScore.staves[i]))
                return i+1;
        return 0;
    }

    function getElementBeat(element)
    {
        let timeSigNum = element.timesigActual.numerator;
        let timeSigDen = element.timesigActual.denominator;
        let absoluteTick = getParentOfType(element, "Segment").tick;
        let firstMeasureTick = getParentOfType(element, "Measure").firstSegment.tick;
        let relativeTick = absoluteTick - firstMeasureTick;
        let totalTickInMeasure = 4 * division * timeSigNum/timeSigDen;
        let beat = Math.floor(relativeTick * timeSigNum / totalTickInMeasure) + 1;
        return beat;
    }

    function getElementClef(element) {
        let testNote = testPitchNearSegment(60, element.parent);
        let posY = testNote.posY;
        cmd("undo");
        return Math.round(posY * 10);
    }

    function testPitchNearSegment(pitch, segment)
    {
        cursor.rewindToTick(segment.tick);
        curScore.startCmd();
        cursor.addNote(pitch);
        curScore.endCmd();
        cursor.prev();
        let retVal = cursor.element.notes[0];
        cmd("undo");
        return retVal;
    }

    function getElementKeySig(element)
    {
        let seg = getParentOfType(element, "Segment");
        cursor.rewindToTick(seg.tick);
        return cursor.keySignature;
    }

    function getElementBPM(element)
    {
        let seg = getParentOfType(element, "Segment");
        let timeSigDen = element.timesigActual.denominator;
        cursor.rewindToTick(seg.tick);
        return Math.round(cursor.tempo * timeSigDen * division / 32);
    }

    /*
     * getMeasure (int) -> Measure
     * Get measure pointer given measure number
     */
    function getMeasure(number)
    {
        let measure = curScore.firstMeasure;
        let counter = 1;
        while (counter++ !== number && measure.nextMeasure !== null)
            measure = measure.nextMeasure;
        return measure;
    }

    function getElementMeasureNumber(element)
    {
        let measure = curScore.firstMeasure;
        let targetMeasure = getParentOfType(element, "Measure");
        let counter = 1;
        while (!measure.is(targetMeasure))
        {
            ++counter;
            measure = measure.nextMeasure;
        }
        return counter;
    }

    function getParentOfType(element, name)
    {
        while(element)
        {
            if(element.name === name)
                return element;
            element = element.parent;
        }
        return null;
    }

    function getStringNumber()
    {
        if(isCursorInTablature())
            return curScore.staves[cursor.staffIdx].part.instruments[0].stringData.strings.length;
        else
            return -1;
    }

    function selectStringFromOdlaKey(odlaKey)
    {
        if(odlaKey < 0)
            return;
        let nStrings = getStringNumber();

        if(nStrings === -1)
            return;

        let string = Math.min(Math.floor(odlaKey / 2), nStrings - 1);

        curScore.startCmd();
        cursor.stringNumber = string;
        curScore.endCmd();
    }

    function stringBelow()
    {
        let nStrings = getStringNumber();
        if(cursor.stringNumber >= nStrings - 1)
        {
            cursor.stringNumber = nStrings - 1;
            return false;
        }
        curScore.startCmd();
        cursor.stringNumber ++;
        curScore.endCmd();
        return true;
    }

    function stringAbove()
    {
        if(cursor.stringNumber <= 0)
        {
            cursor.stringNumber = 0;
            return false;
        }
        curScore.startCmd();
        cursor.stringNumber--;
        curScore.endCmd();
        return true;
    }

    function addNoteToScore(odlaKey, isChord)
    {
        // Add a dummy note
        curScore.startCmd();
        debug("lastVoice: " + lastVoice + " cursor.voice: " + cursor.voice);

        if(cursor.voice === lastVoice)
            cursor.addNote(1, isChord);
        else
            cursor.addNote(1, false);
        lastVoice = cursor.voice;

        // get the note just added
        let n = curScore.selection.elements[0];
        // If current selected element is a rest we insert a new note anyway
        if(n.type !== Element.NOTE)
        {
            cursor.addNote(1);
            n = curScore.selection.elements[0];
        }
        // correct the pitch for the note and its eventually tied note
        adjustNote(n, odlaKey);
        curScore.endCmd();
        playNote(n);
        chordActive = isChord;
    }

    // Can't find another way to play note
    function playNote(note)
    {
        if(note.tpc <= 5)
            cmd("flat2-post");
        else if(note.tpc <= 12)
            cmd("flat-post");
        else if(note.tpc <= 19)
            cmd("nat-post");
        else if(note.tpc <= 26)
            cmd("sharp-post");
        else
            cmd("sharp2-post");
        note.accidentalType = Accidental.NONE;
        cmd("undo");
    }

    function adjustNote(note, odlaKey)
    {
        while(true)
        {
            // if not found we are adding a note to an non-existing chord
            note.line = odlaKey;
            // Correct accidental but first time will only correct the pitch
            note.accidentalType = Accidental.NONE;
            // Second time will correct also tpc
            note.accidentalType = Accidental.NONE;

            if(note.tieBack)
                note = note.firstTiedNote;
            else
                break;
        }
    }

    function removeAccidental(p)
    {
        debug(p);
        let elements = curScore.selection.elements;
        curScore.startCmd();
        for(let i = 0; i < elements.length; i++)
            if(elements[i].type === Element.NOTE)
                elements[i].accidentalType = Accidental.NONE;
        curScore.endCmd();
    }

    function addElement(p)
    {
        let elements = curScore.selection.elements;

        if(elements.length === 0)
            return;
        if(elements.length === 1)
        {
            curScore.startCmd();
            let e = newElement(Element[p.type]);
            e.symbol = SymId[p.symbol];
            cursor.add(e);
            printProperties(e);
            curScore.endCmd();
            return;
        }
        else
        {
            curScore.startCmd();
            let seg = getParentOfType(elements[0], "Segment");
            cursor.rewindToTick(seg.tick);
            for(let i = 0; i < elements.length; i++)
            {
                let e = newElement(Element[p.type]);
                e.symbol = SymId[p.symbol];
                cursor.add(e);
                cursor.next();
            }
            curScore.endCmd();
        }
    }

    function executeShortcut(command)
    {
        if(command === "")
            return;

        switch(command)
        {
        case "next-chord":
            if(!noteInput)
                if(curScore.selection.isRange)
                    setNoteInputMode(true);
                else
                    command = "next-element";
            break;
        case "prev-chord":
            if(!noteInput)
                if(curScore.selection.isRange)
                    setNoteInputMode(true);
                else
                    command = "prev-element";
            break;
        case "up-chord":
            if(isCursorInTablature())
                command = stringAbove() ? "" : "prev-track";
            if(!noteInput)
            {
                if(curScore.selection.isRange)
                    setNoteInputMode(true);
                command = "move-up";
            }
            break;

        case "down-chord":
            if(isCursorInTablature())
                command = stringBelow() ? "" : "next-track";
            if(!noteInput)
            {
                if(curScore.selection.isRange)
                    setNoteInputMode(true);
                command = "move-down";
            }
            break;
        }
        debug("executing: " + command);
        cmd(command);
        afterCommand(command);
    }

    function afterCommand(command)
    {
        switch(command)
        {
        case "hairpin":
            setNoteInputMode(true);
            break;
        }
    }

    // VoiceOver code
    readonly property int noteName        : 1 << 0;
    readonly property int durationName    : 1 << 1;
    readonly property int beatNumber      : 1 << 2;
    readonly property int measureNumber   : 1 << 3;
    readonly property int staffNumber     : 1 << 4;
    readonly property int timeSignFraction: 1 << 5;
    readonly property int clefName        : 1 << 6;
    readonly property int keySignName     : 1 << 7;
    readonly property int voiceNumber     : 1 << 8;
    readonly property int bpmNumber       : 1 << 9;
    readonly property int inputState      : 1 << 10;

    function initSpeechMessage(range)
    {
        // Create message for ODLA VoiceOver
        let message = {};

        // This message is different from old version
        message.version = "MS4";

        // Return package initialized
        return message;
    }

    function createSpeechMessage(flags)
    {
        let message = "";
        let isRange = curScore.selection.isRange;
        let elements = curScore.selection.elements;
        if(elements.length > 0)
        {
            if(isRange)
                message = range_JSON_Info(flags, elements);
            else
                message = element_JSON_Info(flags, elements[0]);
        }
        else
            debug("No element info for speech");
        if(flags & inputState)
            message.IN = noteInput ? "INPUT_ON": "INPUT_OFF";

        debug("sending speech message: " + message);
        return message;
    }

    function element_JSON_Info(flags, element)
    {
        let message = initSpeechMessage(false); //range == false

        if(element.type === Element.NOTE || element.type === Element.REST)
        {
            if (flags & noteName)
            {
                if(isCursorInPitchedStaff())
                {
                    message.unpitched = false;
                    message.tpc = element.tpc;
                }
                else
                {
                    message.unpitched = true;
                }
                message.pitch = getNotePitch(element);

            }

            if (flags & durationName)
            {
                message.durationType = element.durationType.type;
                message.durationDots = element.durationType.dots;
            }

            if (flags & beatNumber)
                message.BEA = getElementBeat(element);

            if (flags & measureNumber)
                message.MEA = getElementMeasureNumber(element);

            if (flags & staffNumber)
                message.STA = getElementStaff(element);

            if (flags & timeSignFraction)
                message.TIM = element.timesigActual.numerator + "/" + element.timesigActual.denominator;

            if (flags & clefName)
                message.CLE = getElementClef(element);

            if (flags & keySignName)
                message.KEY = getElementKeySig(element);

            if (flags & voiceNumber)
                message.VOI = element.voice + 1;

            if (flags & bpmNumber)
                message.BPM = getElementBPM(element);
        }
        else
        {
            let name = element.userName() + " " + element.subtypeName();
            message.elementName = name.toUpperCase().replace(" ", "_");
        }
        return JSON.stringify(message);
    }

    function range_JSON_Info(flags, elements)
    {
        let nEl = elements.length;
        let startElement = elements[0];
        let endElement = elements[nEl-1];
        let message = initSpeechMessage(true); //range == true

        message.RANGE = true;
        message.beatStart = getElementBeat(startElement);
        message.measureStart = getElementMeasureNumber(startElement);
        message.staffStart = curScore.selection.startStaff + 1; // a bug?
        message.beatEnd= getElementBeat(endElement);
        message.measureEnd = getElementMeasureNumber(endElement);
        message.staffEnd = curScore.selection.endStaff;
        return JSON.stringify(message);
    }
    function debug(message)
    {
        console.error("ODLA-Debug: " + message);
    }

    function printProperties(item)
    {
        let properties = "";
        for (let p in item)
            if (typeof item[p] != "function" && typeof item[p] !== 'undefined')
                debug("property " + p + ": " + item[p] + "\n");
    }

    function printFunctions(item)
    {
        let functions = "";
        for (let f in item)
            if (typeof item[f] == "function")
                debug("function: " + f + ": " + item[f] + "\n");
    }

    function sendShuttingDown()
    {
        debug("Quitting");
        Qt.quit();
    }
}
