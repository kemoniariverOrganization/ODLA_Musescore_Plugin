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
        
        var pitch = getPitch(odlaKey, cursor, cursor.keySignature);
        
        curScore.startCmd()
        cursor.addNote(pitch);

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
    
    /*
        The numerical values corresponding to the ODLA keys range
        from -5 (i.e., the note above the second ledger line above the staff)
        to 13 (the note below the second ledger line below the staff)

        The numerical values associated with the vertical position (yPosition)
        of a note on a staff are relative to the first upper line, which is considered 0.
        The space immediately below is considered 0.5, and so on...
    */
    function getPitch(odlaKey, cursor, keySignature)
    {
        // C4 (pitch 60) is the 35th natural note since C-1 (pitch 0)
        var c4Pos = testPitch(cursor, 60).posY;

        // over 4 sharps in key signature pitch60 is considered B#
        if(keySignature >= 4)
            c4Pos -= 0.5;

        // pitchIndex contains an integer representing the number of unaltered
        // (natural) notes starting from the note C-1 (MIDI pitch 0)
        var pitchIndex = 35 - odlaKey + (2 * c4Pos);

        // octave contains the pitch midi of C with the correct octave
        var octave  = Math.floor(pitchIndex / 7) * 12;
        
        switch(pitchIndex % 7)
        {
        case 6:
            if(keySignature >= 7 )
                return octave + 11 + 1;   // B#
            else if (keySignature <= -1)
                return octave + 11 - 1;   // Bb
            else
                return octave + 11;       // B
        case 2:
            if(keySignature >= 6 )
                return octave + 4 + 1;   // E#
            else if (keySignature <= -2)
                return octave + 4 - 1;    // E
            else
                return octave + 4;       // E
        case 5:
            if(keySignature >= 5 )
                return octave + 9 + 1;   // A#
            else if (keySignature <= -3)
                return octave + 9 -1;    // Ab
            else
                return octave + 9;       // A
        case 1:
            if(keySignature >= 4 )
                return octave + 2 + 1;   // D#
            else if (keySignature <= -4)
                return octave + 2 -1;    // Db
            else
                return octave + 2;       // D
        case 4: // G
            if(keySignature >= 3 )
                return octave + 7 + 1;   // G#
            else if (keySignature <= -5)
                return octave + 7 -1;    // Gb
            else
                return octave + 7;       // G
        case 0: // C
            if(keySignature >= 2 )
            return octave + 1;   // C#
        else if (keySignature <= -6)
            return octave -1;    // Cb
        else
            return octave;       // C
        case 3: // F
            if(keySignature >= 1 )
                return octave + 5 + 1;  // F#
            else if (keySignature <= -7)
                return octave + 5 - 1;  // Fb
            else
                return octave + 5;      // F
        }
    }
    
    function debug(message)
    {
        var lines = message.split("\n");
        for (var i = 0; i < lines.length; i++)
            console.log("ODLA-Debug: " + lines[i]);
    }
}
