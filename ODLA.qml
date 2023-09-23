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

                switch (data.par1)
                {
					case "staff-pressed":
						debug("pressed staff n. :" + data.par3)
						var staff_pressed = data.par3;
						addNoteToScore(staff_pressed); // TODO: make command related to clef
						break;

					default:
						var cursor = curScore.newCursor()

						debug("TODO: " + message);
						cursor.inputStateMode=Cursor.INPUT_STATE_SYNC_WITH_SCORE
						curScore.startCmd()
						cmd(data.par1)
						curScore.endCmd()
                }
            });
        }
    }

    property var odlaKeyToPosMap:
    {
        "13": 6.5,
        "12": 6.0,
        "11": 5.5,
        "10": 5.0,
        "9": 4.5,
        "8": 4.0,
        "7": 3.5,
        "6": 3.0,
        "5": 2.5,
        "4": 2.0,
        "3": 1.5,
        "2": 1.0,
        "1": 0.5,
        "0": 0.0,
        "-1": -0.5,
        "-2": -1.0,
        "-3": -1.5,
        "-4": -2.0,
        "-5": -2.5
    }
    // TODO testare solo do centrale (6) e a seconda della y pos trovare la chiave
    /* // creare matrice di pitch e variare seconda della chiave (e poi della tonalità)
    Violino: 5
    Violino+8 = 8.5
    Violino+15 = 12.000000000000002
    Violino-8 = 1.5000000000000002
    Alto = 2
    Tenore = 1
    Basso = -1
    Basso+15 = 6
    Basso+8 = 2.5
    Basso-8 = -4.5
    Basso-15 = -8
    MezzoSoprano = 3.0000000000000004
    Soprano = 4
    Baritono = 0
    */
    property var odlaKeyToPitchMap:
    {
        "13": 55,   // G3
        "12": 57,   // A3
        "11": 59,   // B3
        "10": 60,   // C4
        "9": 62,    // D4
        "8": 64,    // E4
        "7": 65,    // F4
        "6": 67,    // G4
        "5": 69,    // A4
        "4": 71,    // B4
        "3": 72,    // C5
        "2": 74,    // D5
        "1": 76,    // E5
        "0": 77,    // F5
        "-1": 79,   // G5
        "-2": 81,   // A5
        "-3": 83,   // B5
        "-4": 84,   // C6
        "-5": 86    // D6
    }


    function addNoteToScore(odlaKey)
    {
        var cursor = curScore.newCursor()
        cursor.inputStateMode=Cursor.INPUT_STATE_SYNC_WITH_SCORE

        var currentNote = testPos(odlaKeyToPitchMap[odlaKey], odlaKey, cursor)
        var pitchCorrection = ( odlaKeyToPosMap[odlaKey] -  currentNote.posY)

        if(pitchCorrection !== 0)
        {
            for (var key in odlaKeyToPitchMap)
            {
                var corr = pitchCorrection
                while(corr > 0.1)
                {
                    var n = testPos(odlaKeyToPitchMap[key], key, cursor)
                    corr = ( odlaKeyToPosMap[key] -  n.posY).toFixed(1)
                    odlaKeyToPitchMap[key] -= corr
                }
            }
        }

        curScore.startCmd()
        cursor.addNote(odlaKeyToPitchMap[odlaKey])
        playCursor(cursor)
		curScore.endCmd()
    }

    function testPos(pitchToTest, odlaKey, cursor)
    {
        cursor.inputStateMode=Cursor.INPUT_STATE_SYNC_WITH_SCORE
        var key = odlaKey.toString()
        var correctYPos = odlaKeyToPosMap[key]
        curScore.startCmd()
        cursor.addNote(pitchToTest)
        curScore.endCmd()
        cursor.prev()
        var currentNote = cursor.element.notes[0]
        cmd("undo")
        return currentNote
    }

    function listProperties(item) {
        var properties = ""
        for (var p in item)
            if (typeof item[p] != "function")
                properties += (p + ": " + item[p] + "\n")
        return properties
    }

    function listFunctions(item) {
        var functions = ""
        for (var f in item)
            if (typeof item[f] == "function")
                functions += (f + ": " + item[f] + "\n")
        return functions
    }
		
	function playCursor(cursor)
    {
        cursor.prev();
        if(cursor.element == null) 
        {
            cmd("prev-chord");
            cursor.next(); 
            return;
        } 
        if(cursor.element.type != 93) 
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
	
	function debug(message) 
	{
		console.log("ODLA-Debug: " + message);
	}
}
