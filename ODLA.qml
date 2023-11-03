import QtQuick 2.2
import MuseScore 3.0
import QtWebSockets 1.5

MuseScore
{
    version: "3.5"
    description: qsTr("This plugin allows the use of the ODLA keyboard in the Musescore program")
    title: "ODLA"
    categoryCode: "composing-arranging-tools"
    thumbnailName: "ODLA.png"
    requiresScore: false

    onRun:
    {
        debug("ODLA Plugin is running");
    }

    WebSocketServer
    {
        port: 6432
        id: server
        listen: true


        onClientConnected: function(webSocket)
        {
            debug("Client connected")

            webSocket.onTextMessageReceived.connect(function(message)
            {
                var data = JSON.parse(message);
                var cursor = curScore.newCursor()
                //debug("par3: " + data.par3 + " par4: " + data.par4)

                switch (data.par1)
                {
                    case "staff-pressed":
                        addNoteToScore(data.par3);
                        break;

                    default:
                        debug("TODO: " + message);
                        cursor.inputStateMode=Cursor.INPUT_STATE_SYNC_WITH_SCORE
                        curScore.startCmd()
                        cmd(data.par1)
                        curScore.endCmd()
                }
            });
        }
    }

    function addNoteToScore(odlaKey)
    {
        var cursor = curScore.newCursor()
        cursor.inputStateMode=Cursor.INPUT_STATE_SYNC_WITH_SCORE

        var pitch = getPitch(odlaKey, cursor, 0);

        curScore.startCmd()
        cursor.addNote(pitch);

        debug("accidental: " + cursor.element.notes[0].accidental);
        debug("accidentalType: " + cursor.element.notes[0].accidentalType);
        playCursor(cursor)
        curScore.endCmd()
    }

    function testPitch(cursor, pitch)
    {
        cursor.inputStateMode=Cursor.INPUT_STATE_SYNC_WITH_SCORE
        curScore.startCmd()
        cursor.addNote(pitch)
        curScore.endCmd()
        cursor.prev()
        var retVal = cursor.element.notes[0];
        cmd("undo")
        return retVal;
    }

    function listProperties(item) {
        var properties = ""
        for (var p in item)
            if (typeof item[p] != "function")
                properties += ("property " + p + ": " + item[p] + "\n")
        return properties
    }

    function listFunctions(item) {
        var functions = ""
        for (var f in item)
            if (typeof item[f] == "function")
                functions += ("function " + f + ": " + item[f] + "\n")
        return functions
    }

    function playCursor(cursor)
    {
        cursor.prev();
        if(cursor.element === null)
        {
            cmd("prev-chord");
            cursor.next();
            return;
        }
        if(cursor.element.type !== 93)
        {
            cmd("prev-chord");
            cmd("next-chord");
            cursor.next();
            return;
        }
        curScore.selection.select(cursor.element.notes[0]);
        cmd("next-chord");
        cursor.next();
        return;
    }

    function getPitch(odlaKey, cursor, keySignature)
    {
        // C4 is the 35th natural note since C0
        var note60 = testPitch(cursor, 60);
        var pitchIndex = 35 - odlaKey + (2 * note60.posY);
        var pitch = natural_pitch_since_C0(pitchIndex);

        switch (getNote(pitch))
        {
        case "B":
            if(keySignature >= 7 )
                return pitch + 1;
            else if (keySignature <= -1)
                return pitch -1;
            break;
        case "E":
            if(keySignature >= 6 )
                return pitch + 1;
            else if (keySignature <= -2)
                return pitch -1;
            break;
        case "A":
            if(keySignature >= 5 )
                return pitch + 1;
            else if (keySignature <= -3)
                return pitch -1;
            break;
        case "D":
            if(keySignature >= 4 )
                return pitch + 1;
            else if (keySignature <= -4)
                return pitch -1;
            break;
        case "G":
            if(keySignature >= 3 )
                return pitch + 1;
            else if (keySignature <= -5)
                return pitch -1;
            break;
        case "C":
            if(keySignature >= 2 )
                return pitch + 1;
            else if (keySignature <= -6)
                return pitch -1;
            break;
        case "F":
            if(keySignature >= 1 )
                return pitch + 1;
            else if (keySignature <= -7)
                return pitch -1;
            break;
        default:
            return pitch; // should never happen, already accident in pitch
        }
        return pitch; // case without accidental

    }

    function natural_pitch_since_C0(index)
    {
        var octave_offset  = Math.floor(index / 7) * 12;

        switch(index % 7)
        {
            case 0: // C
                return octave_offset;
            case 1: // D
                return octave_offset + 2;
            case 2: // E
                return octave_offset + 4;
            case 3: // F
                return octave_offset + 5;
            case 4: // G
                return octave_offset + 7;
            case 5: // A
                return octave_offset + 9;
            case 6: // B
                return octave_offset + 11;
        }
    }

    function getNote(pitch)
    {
        pitch %= 12;
        switch (pitch)
        {
        case 0 :
            return "C";
        case 1 :
            return "C#Db";
        case 2 :
            return "D";
        case 3 :
            return "D#Eb";
        case 4 :
            return "E";
        case 5 :
            return "F";
        case 6 :
            return "F#Gb";
        case 7 :
            return "G";
        case 8 :
            return "G#Ab";
        case 9 :
            return "A";
        case 10 :
            return "A#Bb";
        case 11 :
            return "B";
        }
        return "unvalid";
    }

    function debug(message)
    {
        var lines = message.split("\n");
        for (var i = 0; i < lines.length; i++)
            console.log("ODLA-Debug: " + lines[i]);
    }
}
