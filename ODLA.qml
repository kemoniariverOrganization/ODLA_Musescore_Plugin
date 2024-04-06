import QtQuick 2.2
import MuseScore 3.0
import QtWebSockets 1.5
import QtQuick.Controls 2.2

MuseScore
{
    version: "3.5"
    description: qsTr("This plugin allows the use of the ODLA keyboard in the Musescore program")
    title: "ODLA"
    //categoryCode: "composing-arranging-tools"
    thumbnailName: "ODLA.png"
    requiresScore: false
    property var latestSegment: null
    property bool noteInput: false
    property var elementCopied: null
    property int noteOffset: 0;
    property bool slur_active: false;

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

            webSocket.onTextMessageReceived.connect(function(message)
            {
                var odlaCommand = JSON.parse(message);
                debug("Message: " + message);

                var cursor = curScore.newCursor();
                cursor.inputStateMode=Cursor.INPUT_STATE_SYNC_WITH_SCORE;

                if ('note_entry' in odlaCommand)
                    setNoteEntry(odlaCommand.note_entry);

                switch (odlaCommand.type)
                {

                case "barline":
                    var type = odlaCommand.value;
                    if(curScore.selection.isRange)
                    {
                        //for (var i = 0; i < selection.elements.length; i++)
                        //debug("element: " + selection.elements[i]);

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
                    addNoteToScore(cursor, odlaCommand.odlaKey, odlaCommand.chord,odlaCommand.slur);
                    break;

                case "accidental":
                    var sym = newElement(Element.SYMBOL);
                    sym.symbol = SymId.accidentalDoubleSharp;
                    sym.offsetX = -1.5;
                    cursor.add(sym);
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
                    var counter = 0;
                    cursor.rewindToTick(0);
                    var measure = cursor.measure;
                    while (++counter !== odlaCommand.value && measure.nextMeasure !== null)
                        measure = measure.nextMeasure;
                    cursor.rewindToTick(measure.firstSegment.tick);
                    cmd("rest");
                    cmd("undo");
                    break;

                default:
                    debug("Shortcut: " + message);
                    curScore.startCmd()
                    cmd(odlaCommand.type)
                    curScore.endCmd()

                    if(odlaCommand.type.includes("hairpin"))
                        cmd("note-input");
                }

                latestSegment = cursor.segment;
            });
        }
    }

    function getNextSeg(obj, type)
    {
        var s = getSegment(obj).next;
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
        var s = getSegment(obj).prev;
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
        var s = getSegment(obj).prev;
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
        var s = getSegment(obj).next;
        while (s)
        {
            var e = s.elementAt(0);
            if (e && e.type === type)
                return e;
            s = s.next;
        }
        return null;
    }

    function getSegment(obj)
    {
        var str = "" + obj.toString();
        if(str.includes("Segment"))
            return obj;
        else if(str.includes("Measure"))
            return obj.lastSegment;
        else if(str.includes("EngravingItem") || str.includes("ChorRest"))
            return obj.parent;
    }

    /*
        I know this is a bad trick, but I didn't find
        a way to know if we are in note-input
        or other state
     */
    function setNoteEntry(status)
    {
        if(status === true && noteInput === false)
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
    }

    function addNoteToScore(cursor, odlaKey, chord, slur)
    {
        var expected_Y = odlaKey / 2.0;
        curScore.startCmd()
        if(slur !== slur_active)
        {
            cmd("add-slur");
            slur_active = !slur_active;
        }
        cmd((chord ? "chord-" : "note-") + getNoteName(odlaKey));
        curScore.endCmd();

        if(cursor.element === null)
            return;

        cursor.prev();

        var curNote = cursor.element.notes[cursor.element.notes.length - 1];
        var current_y = curNote.posY;
        var error = Math.round((expected_Y - current_y) * 2);
        curScore.startCmd()

        while(error !== 0)
        {
            if(error >= 7)
            {
                cmd("pitch-down-octave");
                error -= 7;
            }
            else if(error <= -7)
            {
                cmd("pitch-up-octave");
                error += 7;
            }
            else if(error > 0)
            {
                cmd("pitch-down-diatonic");
                error--;
                noteOffset--;
                noteOffset %= 7;
            }
            else if(error < 0)
            {
                cmd("pitch-up-diatonic");
                error++;
                noteOffset++;
                noteOffset %= 7;
            }
        }
        cursor.inputStateMode=Cursor.INPUT_STATE_SYNC_WITH_SCORE;
        cursor.next();
        curScore.endCmd();
    }

    function getNoteName(odlaKey)
    {
        var note = (13 - odlaKey + noteOffset) % 7;
        while(note < 0)
            note +=7;
        return ["g","a","b","c","d","e","f"][note % 7];
    }

    function printProperties(item)
    {
        var properties = ""
        for (var p in item)
            if (typeof item[p] != "function")
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
