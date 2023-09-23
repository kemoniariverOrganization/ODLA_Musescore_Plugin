import QtQuick 2.15

Item 
{
    property var lookupTable: 
	{
        "13": -2.5,
        "12": -2.0,
        "11": -1.5,
        "10": -1.0,
        "9": -0.5,
        "8": 0.0,
        "7": 0.5,
        "6": 1.0,
        "5": 1.5,
        "4": 2.0,
        "3": 2.5,
        "2": 3.0,
        "1": 3.5,
        "0": 4.0,
        "-1": 4.5,
        "-2": 5.0,
        "-3": 5.5,
        "-4": 6.0,
        "-5": 6.5
    }

    function odlaToStaffPos(odlaKey)
	{
        if (inputNumber in lookupTable) 
		{
            return lookupTable[odlaKey];
        } 
		else 
		{
            throw "KEY NOT PRESENT";
        }
    }
}
