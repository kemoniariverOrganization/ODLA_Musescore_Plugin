import QtQuick 2.2
import MuseScore 3.0
import QtWebSockets 1.5
import QtQuick.Controls 2.2

MuseScore
{
    version: "3.5";
    description: qsTr("This plugin allows the use of the ODLA keyboard in the Musescore program");
    title: "ODLA";
    categoryCode: "composing-arranging-tools"
    thumbnailName: "ODLA.png";
    requiresScore: false;
    property bool toBeRead: false;
    property int newElementTick: 0;
    property var cursor: null;
    property bool noteInput: false;

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

    onRun:
    {
        debug("ODLA Plugin is running");
    }

    WebSocketServer
    {
        port: 6433
        id: server
        listen: true

        onClientConnected: function(webSocket)
        {
            debug("Client connected");

            cursor = curScore.newCursor();
            if(cursor === null)
            {
                debug("Can't create cursor ...")
                return;
            }
            cursor.inputStateMode=Cursor.INPUT_STATE_SYNC_WITH_SCORE;

            setNoteEntry(true);

            function parseCommand(command)
            {
                newElementTick = cursor.tick;
                if(!cursor.score.is(curScore))
                {
                    cursor = curScore.newCursor();
                    cursor.inputStateMode=Cursor.INPUT_STATE_SYNC_WITH_SCORE;
                }
                debug("Received command: " + command);
                var odlaCommand = JSON.parse(command);

                if ('SpeechFlags' in odlaCommand)
                {
                    voiceOver(odlaCommand.SpeechFlags);
                    return;
                }

                if ('note_entry' in odlaCommand)
                    setNoteEntry(odlaCommand.note_entry);

                switch (odlaCommand.type)
                {

                case "barline":
                    var type = odlaCommand.value;
                    if(curScore.selection.isRange)
                    {
                        var selection = curScore.selection;
                        var startSegment = selection.startSegment;
                        var endSegment = selection.endSegment;
                        curScore.startCmd();

                        if(type === 4 || type === 8)
                        {
                            // start repeat buggy https://musescore.org/it/node/345122
                            var start_bar = getPrevEl(startSegment, Element.BAR_LINE);
                            start_bar = getPrevEl(start_bar, Element.BAR_LINE);

                            if(start_bar)
                                start_bar.barlineType = 4;

                            var end_bar = getNextEl(endSegment, Element.BAR_LINE);
                            if(end_bar)
                                end_bar.barlineType = 8;
                        }
                        else
                        {
                            var s = getNextSeg(startSegment, Segment.BarLineType);
                            while (s && !s.parent.is(endSegment.parent))
                            {
                                var e = s.elementAt(cursor.track);
                                e.barlineType = type;
                                s = getNextSeg(s, Segment.BarLineType);
                            }
                        }
                        curScore.endCmd();
                    }
                    else
                    {

                        var bar = null;

                        if(type === 4)// start repeat buggy https://musescore.org/it/node/345122
                        {
                            bar = getPrevEl(cursor.segment, Element.BAR_LINE);
                            bar = getPrevEl(bar, Element.BAR_LINE);
                        }
                        else
                        {
                            bar = getNextEl(cursor.segment, Element.BAR_LINE);
                        }
                        if(bar !== null)
                        {
                            curScore.startCmd();
                            bar.barlineType = type;
                            var nextBarline = getNextEl(bar, Element.BAR_LINE);
                            // since start repeat (4) is placed as first segment of next measure
                            if(nextBarline.barlineType === 4)
                                nextBarline.barlineType = 1;
                            curScore.endCmd();
                        }
                    }
                    break;
                case "select-measures":
                    var firstMeasure = getMeasure(odlaCommand.firstMeasure);
                    var lastMeasure = getMeasure(odlaCommand.lastMeasure);


                    var startTick = firstMeasure.firstSegment.tick;
                    var endTick = lastMeasure.lastSegment.tick;

                    curScore.startCmd();
                    curScore.selection.selectRange(startTick, endTick+1, 0, curScore.nstaves)
                    curScore.endCmd();

                    break;
                case "dynamics":
                    var dyn = newElement(Element.DYNAMIC);
                    dyn.subtype = odlaCommand.subtype;
                    dyn.text = odlaCommand.text;
                    curScore.startCmd();
                    cursor.add(dyn);
                    curScore.endCmd();
                    break;

                case "time-signature":
                    var ts=newElement(Element.TIMESIG);
                    ts.timesig=fraction(odlaCommand.numerator,odlaCommand.denominator);
                    curScore.startCmd();
                    cursor.add(ts);
                    curScore.endCmd();
                    // TODO: common time and alla breve
                    break;

                case "staff-pressed":
                    if(!isCursorInTablature())
                        addNoteToScore(odlaCommand.odlaKey, odlaCommand.chord);
                    else
                        selectStringFromOdlaKey(odlaCommand.odlaKey);
                    break;

                case "insert-measures":
                    curScore.startCmd();
                    curScore.appendMeasures(odlaCommand.value ? odlaCommand.value : 1);
                    curScore.endCmd();
                    break;

                case "tempo":
                    var tempo = newElement(Element.TEMPO_TEXT);
                    tempo.followText = 1; // va aggiornato ?
                    tempo.text = odlaCommand.text;
                    tempo.tempo = parseFloat(odlaCommand.tempo / odlaCommand.time_divider);
                    curScore.startCmd();
                    cursor.add(tempo);
                    curScore.endCmd();

                    break;
                case "goto":
                    var currentMeasureNumber = getElementMeasureNumber(cursor.element);

                    while(currentMeasureNumber !== odlaCommand.value)
                    {
                        if(currentMeasureNumber > odlaCommand.value)
                        {
                            cmd("notation-move-left-quickly");
                            currentMeasureNumber--;
                        }
                        else
                        {
                            cmd("notation-move-right-quickly");
                            currentMeasureNumber++;
                        }
                    }
                    break;

                case "note-input":
                    setNoteEntry(!noteInput);
                    break;

                default:
                    odlaCommand.type = replaceCommand(odlaCommand.type);
                    if(odlaCommand.type === "")
                        return
                    debug("executing: " + odlaCommand.type);
                    cmd(odlaCommand.type);
                    afterCommand(odlaCommand.type);
                }
            }

            function replaceCommand(command)
            {
                switch(command)
                {
                case "next-chord":
                    if(!noteInput)
                        if(curScore.selection.isRange)
                            setNoteEntry(true);
                        else
                            return "next-element";
                    break;
                case "prev-chord":
                    if(!noteInput)
                        if(curScore.selection.isRange)
                            setNoteEntry(true);
                        else
                            return "prev-element";
                    break;
                case "up-chord":
                    if(isCursorInTablature())
                        return stringAbove() ? "" : "prev-track";
                    if(!noteInput)
                        return "move-up";
                    break;
                case "down-chord":
                    if(isCursorInTablature())
                        return stringBelow() ? "" : "next-track";
                    if(!noteInput)
                        return "move-down";
                    break;
                default:
                    return command;
                }
                return command;
            }
            function afterCommand(command)
            {
                switch(command)
                {
                case "hairpin":
                    setNoteEntry(true);
                    break;
                }
            }

            function voiceOver(SpeechFlags, extra = "")
            {
                // Create message for ODLA VoiceOver
                var toSay = {};
                // This message is different from old version
                toSay.version = "MS4";

                let toReadElement = null;
                // if(toBeRead)
                toReadElement = curScore.selection.elements[0];
                // else
                //     toReadElement = getTickElement(newElementTick);

                var seg = getParentOfType(toReadElement, "Segment");


                if(curScore.selection.isRange)
                {
                    var nEl = curScore.selection.elements.length;
                    var startElement = curScore.selection.elements[0];
                    var endElement = curScore.selection.elements[nEl-1];

                    toSay.RANGE = true;
                    toSay.beatStart = getElementBeat(startElement);
                    toSay.measureStart = getElementMeasureNumber(startElement);
                    toSay.staffStart = curScore.selection.startStaff + 1; // a bug?
                    toSay.beatEnd= getElementBeat(endElement);
                    toSay.measureEnd = getElementMeasureNumber(endElement);
                    toSay.staffEnd = curScore.selection.endStaff;
                }
                else if(toReadElement.type === Element.NOTE || toReadElement.type === Element.REST)
                {
                    if (SpeechFlags & noteName)
                    {
                        toSay.pitch = getNotePitch(toReadElement);
                        toSay.tpc = toReadElement.tpc;
                    }

                    if (SpeechFlags & durationName)
                    {
                        toSay.durationType = toReadElement.durationType.type;
                        toSay.durationDots = toReadElement.durationType.dots;
                    }

                    if (SpeechFlags & beatNumber)
                        toSay.BEA = getElementBeat(toReadElement);

                    if (SpeechFlags & measureNumber)
                        toSay.MEA = getElementMeasureNumber(toReadElement);

                    if (SpeechFlags & staffNumber)
                        toSay.STA = getElementStaff(toReadElement);

                    if (SpeechFlags & timeSignFraction)
                        toSay.TIM = toReadElement.timesigActual.numerator + "/" + toReadElement.timesigActual.denominator;

                    if (SpeechFlags & clefName)
                        toSay.CLE = getElementClef(toReadElement);

                    if (SpeechFlags & keySignName)
                        toSay.KEY = getElementKeySig(toReadElement);

                    if (SpeechFlags & voiceNumber)
                        toSay.VOI = toReadElement.voice + 1;

                    if (SpeechFlags & bpmNumber)
                        toSay.BPM = getElementBPM(toReadElement);
                }
                else
                    toSay.elementName = toReadElement.userName().toUpperCase();
                if(SpeechFlags === inputState)
                    toSay.IN = noteInput ? "INPUT_ON": "INPUT_OFF";

                debug(JSON.stringify(toSay));
                webSocket.sendTextMessage(JSON.stringify(toSay));
                toBeRead = false;
            }

            // Bad way (wait for better API) to ensure note input
            function setNoteEntry(status)
            {
                if(status === true && (noteInput === false || curScore.selection.elements.length === 0))
                {
                    cmd("note-input-steptime");
                    noteInput = true;
                }
                else if(status === false && noteInput === true)
                {
                    cmd("notation-escape");
                    noteInput = false;
                }
            }
            webSocket.onTextMessageReceived.connect(parseCommand);
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

    function getTickElement(tick)
    {
        let currentTick = cursor.tick;
        cursor.rewindToTick(tick);
        let retVal = cursor.element;
        cursor.rewindToTick(currentTick);
        return retVal;
    }

    /*
     * getNotePitch (Element) -> int
     * Get note pitch of Element or -1 if it's a pause
     */
    function getNotePitch(element){
        if(element.type === Element.NOTE)
            return element.pitch;
        if(element.type === Element.CHORD)
            return element.notes[0].pitch;
        else if(element.type === Element.REST)
            return -1;
        else
            return -2;
    }

    function getElementStaff(element) {
        for(let i = 0; i < curScore.nstaves; i++)
            if(element.staff.is(curScore.staves[i]))
                return i+1;
        return 0;
    }

    function getElementBeat(element) {

        var timeSigNum = element.timesigActual.numerator;
        var timeSigDen = element.timesigActual.denominator;
        var absoluteTick = getParentOfType(element, "Segment").tick;
        var firstMeasureTick = getParentOfType(element, "Measure").firstSegment.tick;
        var relativeTick = absoluteTick - firstMeasureTick;
        var totalTickInMeasure = 4 * division * timeSigNum/timeSigDen;
        var beat = Math.floor(relativeTick * timeSigNum / totalTickInMeasure) + 1;
        return beat;
    }

    function getElementClef(element) {
        var testNote = testPitchNearSegment(60, element.parent);
        var posY = testNote.posY;
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
        var retVal = cursor.element.notes[0];
        cmd("undo");
        return retVal;
    }

    // Can't find another way to play note
    function playNote(note, chord)
    {
        //let nextTick = cursor.tick;
        //cursor.rewindToTick(note.tick);
        cmd("next-chord");
        cmd("prev-chord");
        if(!chord)
            cursor.next();
        //cursor.rewindToTick(nextTick);
    }

    function getElementKeySig(element)
    {
        var seg = getParentOfType(element, "Segment");
        cursor.rewindToTick(seg.tick);
        return cursor.keySignature;
    }

    function getElementBPM(element)
    {
        var seg = getParentOfType(element, "Segment");
        var timeSigDen = element.timesigActual.denominator;
        cursor.rewindToTick(seg.tick);
        return Math.round(cursor.tempo * timeSigDen * division / 32);
    }

    /*
     * getMeasure (int) -> Measure
     * Get measure pointer given measure number
     */
    function getMeasure(number)
    {
        var measure = curScore.firstMeasure;
        var counter = 1;
        while (counter++ !== number && measure.nextMeasure !== null)
            measure = measure.nextMeasure;
        return measure;
    }

    function getElementMeasureNumber(element)
    {
        var measure = curScore.firstMeasure;
        var targetMeasure = getParentOfType(element, "Measure");
        var counter = 1;
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

    function getNextSeg(obj, type)
    {
        var s = getParentOfType(obj, "Segment").next;
        while (s)
        {
            if (s.segmentType & type)
                return s;
            s = s.next;
        }
        return null;
    }

    function getPrevSeg(segment, type)
    {
        var s = getParentOfType(obj, "Segment").prev;
        while (s)
        {
            if (s.segmentType & type) // segment type is a flag
                return s;
            s = s.prev;
        }
        return null;
    }

    function getPrevEl(obj, type)
    {
        var s = getParentOfType(obj, "Segment").prev;
        while (s)
        {
            var e = s.elementAt(cursor.track);
            if (e && e.type === type)
                return e;
            s = s.prev;
        }
        return null;
    }

    function getNextEl(obj, type)
    {
        var s = getParentOfType(obj, "Segment").next;
        while (s)
        {
            var e = s.elementAt(cursor.track);
            if (e && e.type === type)
                return e;
            s = s.next;
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
        var nStrings = getStringNumber();

        if(nStrings === -1)
            return;

        var string = Math.min(Math.floor(odlaKey / 2), nStrings - 1);

        curScore.startCmd();
        cursor.stringNumber = string;
        curScore.endCmd();
    }

    function stringBelow()
    {
        var nStrings = getStringNumber();

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
    function getInsertedNote(tick, pitchesList)
    {
        cursor.rewindToTick(tick);
        let notesList = cursor.element.notes;
        if(notesList === 'undefined' || notesList.length === 0)
            return null;
        if(notesList.length === 1)
            return notesList[0];

        let found = false;
        for(let i = 0; i < notesList.length; i++)
        {
            debug("noteList[" + i + "] = " + notesList[i].pitch);
            if(!pitchesList.includes(notesList[i].pitch))
                return notesList[i];
        }
        return null;
    }

    function pitchesList(tick)
    {
        cursor.rewindToTick(tick);
        let el = cursor.element;

        let retVal = [];

        if(el.type === Element.CHORD)
            for(let i = 0; i < el.notes.length; i++)
                retVal[i] = el.notes[i].pitch;
        return retVal;
    }


    function addNoteToScore(odlaKey, chord)
    {
        // save pitches list at cursor before note insertion
        // let pitchesBefore = pitchesList(newElementTick);

        curScore.startCmd();

        // Add a dummy note
        cmd(chord /*&& cursor.element.type === Element.CHORD*/? "chord-g" : "note-g");

        // store cursor position
        let tickAfter= cursor.tick;

        //        // move cursor to the beginning of insertion (case multiple notes tied)
        //        cursor.rewindToTick(newElementTick);

        // correct the pitch for each notes
        let n = curScore.selection.elements[0];

        adjustNote(n, odlaKey)


        curScore.endCmd();
        // The only way to play just inserted note
        playNote(n, chord);

        toBeRead = true;
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


    function printProperties(item)
    {
        var properties = ""
        for (var p in item)
            if (typeof item[p] != "function" && typeof item[p] !== 'undefined')
                console.log("property " + p + ": " + item[p] + "\n");
    }

    function printFunctions(item)
    {
        var functions = ""
        for (var f in item)
            if (typeof item[f] == "function")
                console.log("function: " + f + ": " + item[f] + "\n");
    }

    function debug(message)
    {
        console.log("ODLA-Debug: " + message);
    }
}
