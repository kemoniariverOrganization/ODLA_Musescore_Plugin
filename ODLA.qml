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
    property var latestElement: null;
    property var latestChord: null;
    property var cursor: null;
    property bool noteInput: false;
    property int noteOffset: 0;
    property bool slur_active: false;
    property bool chord_active: false;
    property var accidentalActive: Accidental.NONE;

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

    onRun:
    {
        debug("ODLA Plugin is running");
        cursor = curScore.newCursor();
        cursor.inputStateMode=Cursor.INPUT_STATE_SYNC_WITH_SCORE;
    }

    WebSocketServer
    {
        port: 6433
        id: server
        listen: true

        onClientConnected: function(webSocket)
        {
            debug("Client connected");

            setNoteEntry(true);

            webSocket.onTextMessageReceived.connect(function(message)
            {
                var odlaCommand = JSON.parse(message);
                debug("Message: " + message);

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
                                var e = s.elementAt(0);
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

                    //setCursorToTime(cursor, startTick);
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
                        addNoteToScore(odlaCommand.odlaKey, odlaCommand.chord, odlaCommand.slur);
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

                latestChord = getThisOrPrevChord();
            });

            function replaceCommand(command)
            {
                switch(command)
                {
                case "next-chord":
                    if(!noteInput)
                        return "next-element";
                    break;
                case "prev-chord":
                    if(!noteInput)
                        return "prev-element";
                    break;
                case "up-chord":
                    if(isCursorInTablature())
                        return stringAbove() ? "" : "prev-track";
                    break;
                case "down-chord":
                    if(isCursorInTablature())
                        return stringBelow() ? "" : "next-track";
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
                case "sharp":
                case "sharp2":
                case "flat":
                case "flat2":
                case "nat":
                    cmd("note-g");
                    accidentalActive = getThisOrPrevChord().notes[0].accidentalType;
                    cmd("undo");
                    break;

                }
            }
            function voiceOver(SpeechFlags)
            {
                var toSay = {};

                toSay.version = "MS4";

                if(curScore.selection.isRange)
                {
                    var startElement = curScore.selection.startSegment.elementAt(0);
                    var endElement = curScore.selection.endSegment.elementAt(0);

                    toSay.RANGE = true;
                    toSay.beatStart = getElementBeat(startElement);
                    toSay.measureStart = getElementMeasureNumber(startElement);
                    toSay.staffStart = getElementStaff(startElement);
                    toSay.beatEnd= getElementBeat(endElement);
                    toSay.measureEnd = getElementMeasureNumber(endElement);
                    toSay.staffEnd = getElementStaff(endElement);
                }
                else
                {
                    if(!toBeRead)
                        latestElement = getLastSelectedElement();

                    if (SpeechFlags & noteName)
                    {
                        toSay.pitch = getNotePitch(latestElement);
                        toSay.tpc = latestElement.tpc;
                    }

                    if (SpeechFlags & durationName)
                    {
                        toSay.durationType = latestElement.durationType.type;
                        toSay.durationDots = latestElement.durationType.dots;
                    }

                    if (SpeechFlags & beatNumber)
                        toSay.BEA = getElementBeat(latestElement);

                    if (SpeechFlags & measureNumber)
                        toSay.MEA = getElementMeasureNumber(latestElement);

                    if (SpeechFlags & staffNumber)
                        toSay.STA = getElementStaff(latestElement);

                    if (SpeechFlags & timeSignFraction)
                        toSay.TIM = latestElement.timesigActual.numerator + "/" + latestElement.timesigActual.denominator;

                    if (SpeechFlags & clefName)
                        toSay.CLE = getElementClef(latestElement);

                    if (SpeechFlags & keySignName)
                        toSay.KEY = getElementKeySig(latestElement);

                    if (SpeechFlags & voiceNumber)
                        toSay.VOI = latestElement.voice + 1;

                    if (SpeechFlags & bpmNumber)
                        toSay.BPM = getElementBPM(latestElement);
                }
                debug(JSON.stringify(toSay));
                webSocket.sendTextMessage(JSON.stringify(toSay));
                toBeRead = false;
            }
        }
    }

    function isCursorInTablature()
    {
        try {
            debug("Tablature? " + curScore.staves[cursor.staffIdx].part.hasTabStaff);
            return curScore.staves[cursor.staffIdx].part.hasTabStaff;
        } catch (error) {
            return false;
        }
    }

    function getLastSelectedElement()
    {
        var nEl = curScore.selection.elements.length;
        return (nEl===0) ? null : curScore.selection.elements[nEl-1];
    }

    function getThisOrPrevChord()
    {
        var seg = cursor.segment;
        while(seg)
        {
            var chord = seg.elementAt(cursor.track);
            if(chord.type !== Element.CHORD)
                seg = seg.prev;
            else return chord;
        }
        return null;
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
        var seg = getParentOfType(element, "Segment");
        var staffNumber = element.track;
        //var instrumentName = element.staff.part.instrumentAtTick(seg.tick).longName;
        return (staffNumber+1);
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

    function playCursor()
    {
        // I cannot find another way to play note
        cmd("prev-chord");
        cmd("next-chord");

    }

    function getElementKeySig(element) {
        var seg = getParentOfType(element, "Segment");
        cursor.rewindToTick(seg.tick);
        return cursor.keySignature;
    }

    function getElementBPM(element) {
        var seg = getParentOfType(element, "Segment");
        var timeSigDen = element.timesigActual.denominator;
        cursor.rewindToTick(seg.tick);
        return Math.round(cursor.tempo * timeSigDen * division / 32);
    }

    /*
     * getMeasure (int) -> Measure
     * Get measure pointer given measure number
     */
    function getMeasure(number){
        var measure = curScore.firstMeasure;
        var counter = 1;
        while (counter++ !== number && measure.nextMeasure !== null)
            measure = measure.nextMeasure;
        return measure;
    }

    function getElementMeasureNumber(element){
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

    function setCursorToTime(cursor, time){
        cursor.rewind(0);
        while (cursor.segment) {
            var current_time = cursor.tick;
            if(current_time>=time){
                return true;
            }
            cursor.next();
        }
        cursor.rewind(0);
        return false;
    }// end setcursor To Time

    function getNextSeg(obj, type)
    {
        var s = getParentOfType(obj, "Segment").next;
        while (s)
        {
            debug("trovato: " + s.segmentType + " cercato: " + type);
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
            debug("trovato: " + s.segmentType + " cercato: " + type);
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
            var e = s.elementAt(0);
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
            var e = s.elementAt(0);
            if (e && e.type === type)
                return e;
            s = s.next;
        }
        return null;
    }

    /*
        I know this is a bad trick, but I didn't find
        a way to know if we are in note-input
        or other state
     */
    function setNoteEntry(status)
    {
        if(status === true && (noteInput === false || curScore.selection.elements.length === 0))
        {
            cmd("note-input-steptime");
            noteInput = true;
        }
        else if(status === false && noteInput === true)
        {
            //cmd("toggle-insert-mode");
            cmd("notation-escape");
            noteInput = false;
        }
        debug("cursor selection " + noteInput);
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
        if(cursor.stringNumber === nStrings - 1)
            return false;
        if(cursor.stringNumber)
        {
            curScore.startCmd();
            cursor.stringNumber++;
            curScore.endCmd();
        }
        return true;
    }

    function stringAbove()
    {
        if(cursor.stringNumber === 0)
            return false;
        if(cursor.stringNumber)
        {
            curScore.startCmd();
            cursor.stringNumber--;
            curScore.endCmd();
        }
        return true;
    }
    function getNoteFromChord(chord, pitch)
    {
        for(var i = chord.notes.length - 1; i >= 0; i--)
        {
            var note = chord.notes[i];
            if(note.pitch === pitch)
                return note;
        }
        return null;
    }

    function lineToPitch(line)
    {
        // Add a temp note (with undoable action)
        curScore.startCmd();
        cursor.addNote(1);
        // get note object
        var lastChord = getThisOrPrevChord();
        var note = getNoteFromChord(lastChord, 1);

        // correct note line with odla odla choosen one
        note.line = line;
        note.accidentalType = Accidental.NONE; // first time for old note
        note.accidentalType = Accidental.NONE; // second time for new note
        var pitch = note.pitch;
        curScore.endCmd();
        cmd("undo");
        return pitch;
    }

    function addNoteToScore(odlaKey, chord, slur)
    {
//        if(slur !== slur_active) // TODO: risolvere doppia attivazione
//        {
//            cmd("add-slur");
//            slur_active = !slur_active;
//        }
        if(!chord) // chord deactivation will affect this insertion
            chord_active = false;

        var pitch = lineToPitch(odlaKey);
        curScore.startCmd();

        let n = null;
        if(chord_active && latestChord !==null)
        {
            n = newElement(Element.NOTE);
            latestChord.add(n);
            n.line = odlaKey;
            n.accidentalType = accidentalActive;
            n.accidentalType = accidentalActive;
        }
        else
        {
            cursor.addNote(pitch, chord_active);
            n = getNoteFromChord(getThisOrPrevChord(), pitch);
            n.line = odlaKey;
            n.accidentalType = accidentalActive;
        }
        curScore.endCmd();
        playCursor();
        if(chord) // chord activation will affect next insertion
            chord_active = true;
        latestElement = n;
        toBeRead = true;
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
