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
                case "dynamics":
                    var dyn = newElement(Element.DYNAMIC);
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
                    tempo.text = odlaCommand.text + odlaCommand.tempo;
                    tempo.tempo = parseFloat(odlaCommand.tempo);
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
                    cursor.inputStateMode=Cursor.INPUT_STATE_SYNC_WITH_SCORE;
                    break;

                default:
                    debug("Shortcut: " + message);
                    curScore.startCmd()
                    cmd(odlaCommand.type)
                    curScore.endCmd()
                }

                latestSegment = cursor.segment;
            });
        }
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
        cursor.prev();
        var curNote = cursor.element.notes[cursor.element.notes.length - 1];

        var current_y = curNote.posY;
        var error = Math.round((expected_Y - current_y) * 2);

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
