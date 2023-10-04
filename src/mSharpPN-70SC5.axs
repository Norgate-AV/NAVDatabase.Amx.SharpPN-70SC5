MODULE_NAME='mSharpPN-70SC5'    (
                                    dev vdvControl,
                                    dev dvPort
                                )

(***********************************************************)
#include 'NAVFoundation.ModuleBase.axi'
#include 'NAVFoundation.Math.axi'
#include 'NAVFoundation.SocketUtils.axi'

/*
 _   _                       _          ___     __
| \ | | ___  _ __ __ _  __ _| |_ ___   / \ \   / /
|  \| |/ _ \| '__/ _` |/ _` | __/ _ \ / _ \ \ / /
| |\  | (_) | | | (_| | (_| | ||  __// ___ \ V /
|_| \_|\___/|_|  \__, |\__,_|\__\___/_/   \_\_/
                 |___/

MIT License

Copyright (c) 2023 Norgate AV Services Limited

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

(***********************************************************)
(*          DEVICE NUMBER DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_DEVICE

(***********************************************************)
(*               CONSTANT DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_CONSTANT

constant long TL_DRIVE    = 1
constant long TL_IP_CHECK = 2

constant integer REQUIRED_POWER_ON    = 1
constant integer REQUIRED_POWER_OFF    = 2

constant integer ACTUAL_POWER_ON    = 1
constant integer ACTUAL_POWER_OFF    = 2

constant integer REQUIRED_INPUT_HDMI_1    = 1
constant integer REQUIRED_INPUT_HDMI_2    = 2
constant integer REQUIRED_INPUT_HDMI_3    = 3
constant integer REQUIRED_INPUT_HDMI_4    = 4
constant integer REQUIRED_INPUT_PC    = 5

constant integer ACTUAL_INPUT_HDMI_1    = 1
constant integer ACTUAL_INPUT_HDMI_2    = 2
constant integer ACTUAL_INPUT_HDMI_3    = 3
constant integer ACTUAL_INPUT_HDMI_4    = 4
constant integer ACTUAL_INPUT_PC    = 5

constant char INPUT_COMMANDS[][NAV_MAX_CHARS]    = { '1',
                            '2',
                            '3',
                            '4',
                            '5' }

constant integer GET_POWER    = 1
constant integer GET_INPUT    = 2
constant integer GET_MUTE    = 3
constant integer GET_VOLUME    = 4

constant integer REQUIRED_MUTE_ON    = 1
constant integer REQUIRED_MUTE_OFF    = 2

constant integer ACTUAL_MUTE_ON    = 1
constant integer ACTUAL_MUTE_OFF    = 2

constant integer MAX_VOLUME = 100
constant integer MIN_VOLUME = 0

(***********************************************************)
(*              DATA TYPE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_TYPE

(***********************************************************)
(*               VARIABLE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_VARIABLE

volatile long ltIPCheck[] = { 3000 }    //3 seconds
volatile _NAVDisplay uDisplay

volatile integer iLoop
volatile integer iPollSequence = GET_POWER

volatile integer iRequiredPower
volatile integer iRequiredInput
volatile integer iRequiredMute
volatile sinteger iRequiredVolume = 1

volatile long ltDrive[] = { 200 }

volatile integer iSemaphore
volatile char cRxBuffer[NAV_MAX_BUFFER]

volatile integer iModuleEnabled

volatile integer iPowerBusy

volatile char cIPAddress[15]
volatile integer iTCPPort
volatile integer iIPConnected = false

volatile integer iCommandBusy
volatile integer iCommandLockOut

volatile integer iCommunicating

volatile integer iWaitBusy

volatile integer iID = 1

volatile integer iInputInitialized
volatile integer iVolumeIntialized
volatile integer iAudioMuteInitialized

(***********************************************************)
(*               LATCHING DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_LATCHING

(***********************************************************)
(*       MUTUALLY EXCLUSIVE DEFINITIONS GO BELOW           *)
(***********************************************************)
DEFINE_MUTUALLY_EXCLUSIVE

(***********************************************************)
(*        SUBROUTINE/FUNCTION DEFINITIONS GO BELOW         *)
(***********************************************************)
(* EXAMPLE: DEFINE_FUNCTION <RETURN_TYPE> <NAME> (<PARAMETERS>) *)
(* EXAMPLE: DEFINE_CALL '<NAME>' (<PARAMETERS>) *)
define_function SendStringRaw(char cParam[]) {
     NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_TO, dvPort, cParam))
    send_string dvPort,"cParam"
}

define_function SendString(char cParam[]) {
    SendStringRaw("cParam,NAV_CR")
}

define_function SendQuery(integer iParam) {
    switch (iParam) {
    case GET_POWER: SendString("'POWR????'")
    case GET_INPUT: SendString("'IAVD????'")
    case GET_MUTE: SendString("'MUTE????'")
    case GET_VOLUME: SendString("'VOLM????'")
    }
}

define_function TimeOut() {
    cancel_wait 'CommsTimeOut'
    wait 300 'CommsTimeOut' { iCommunicating = false }
}

define_function SetPower(integer iParam) {
    switch (iParam) {
    case REQUIRED_POWER_ON: { SendString("'POWR1   '") }
    case REQUIRED_POWER_OFF: { SendString("'POWR0   '") }
    }
}

define_function SetInput(integer iParam) { SendString("'IAVD',INPUT_COMMANDS[iParam],'   '") }

define_function SetVolume(sinteger siParam) { SendString("'VOLM',format('%03d',siParam),' '") }

define_function SetMute(integer iParam) {
    switch (iParam) {
    case REQUIRED_MUTE_ON: { SendString("'MUTE1   '") }
    case REQUIRED_MUTE_OFF: { SendString("'MUTE2   '") }
    }
}

define_function Process() {
    stack_var char cTemp[NAV_MAX_BUFFER]
    iSemaphore = true
    while (length_array(cRxBuffer) && NAVContains(cRxBuffer,"NAV_CR")) {
    cTemp = remove_string(cRxBuffer,"NAV_CR",1)
    if (length_array(cTemp)) {
         NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_PARSING_STRING_FROM, dvPort, cTemp))
        cTemp = NAVStripCharsFromRight(cTemp, 1)    //Removes CR
        select {
        active (NAVContains(cTemp,'ERR') || NAVContains(cTemp,"$FF,$FF,$FF")): {

        }
        active (NAVContains(cTemp,'WAIT')): {
            iWaitBusy = true
            wait 100 'WaitBusy' iWaitBusy = false    //Force it off after 10 seconds just incase
        }
        active (NAVContains(cTemp,'OK')): {
            cancel_wait 'WaitBusy'
            iWaitBusy = false
        }
        active (NAVContains(cTemp,'LOCKED')): {

        }
        active (NAVContains(cTemp,'UNSELECTED')): {

        }
        active (1): {
            switch (iPollSequence) {
            case GET_POWER: {
                switch (cTemp) {
                case '0': { uDisplay.PowerState.Actual = ACTUAL_POWER_OFF;  }
                case '1':
                case '2': {
                    uDisplay.PowerState.Actual = ACTUAL_POWER_ON;
                    //select {
                    //active (!iInputInitialized): {
                        //iPollSequence = GET_INPUT
                    //}
                    //active (!iVolumeIntialized): {
                        //iPollSequence = GET_VOLUME
                    //}
                    //active (!iAudioMuteInitialized): {
                        //iPollSequence = GET_MUTE
                    //}
                    //}
                }
                }
            }
            case GET_INPUT: {
                switch (cTemp) {
                case '1': { uDisplay.Input.Actual = ACTUAL_INPUT_HDMI_1; iInputInitialized = true; iPollSequence = GET_POWER }
                case '2': { uDisplay.Input.Actual = ACTUAL_INPUT_HDMI_2; iInputInitialized = true; iPollSequence = GET_POWER }
                case '3': { uDisplay.Input.Actual = ACTUAL_INPUT_HDMI_3; iInputInitialized = true; iPollSequence = GET_POWER }
                case '4': { uDisplay.Input.Actual = ACTUAL_INPUT_HDMI_4; iInputInitialized = true; iPollSequence = GET_POWER }
                case '5': { uDisplay.Input.Actual = ACTUAL_INPUT_PC; iInputInitialized = true; iPollSequence = GET_POWER }
                }
            }
            case GET_MUTE: {
                switch (cTemp) {
                case '2': { uDisplay.Volume.Mute.Actual = ACTUAL_MUTE_OFF; iAudioMuteInitialized = true; iPollSequence = GET_POWER }
                case '1': { uDisplay.Volume.Mute.Actual = ACTUAL_MUTE_ON; iAudioMuteInitialized = true; iPollSequence = GET_POWER }
                }
            }
            case GET_VOLUME: {
                if (atoi(cTemp) <> uDisplay.Volume.Level.Actual) {
                uDisplay.Volume.Level.Actual = atoi(cTemp)
                send_level vdvControl, VOL_LVL, NAVScaleValue(uDisplay.Volume.Level.Actual, 255, (MAX_VOLUME - MIN_VOLUME), 0)
                }

                iVolumeIntialized = true
                iPollSequence = GET_POWER
            }
            }
        }
        }
    }
    }

    iSemaphore = false
}

define_function Drive() {
    iLoop++
    switch (iLoop) {
    case 1:
    case 6:
    case 11:
    //case 16: { SendQuery(iPollSequence); return }
    case 21: { iLoop = 1; return }
    default: {
        if (iCommandLockOut || iWaitBusy) { return }
        if (iRequiredPower && (iRequiredPower == uDisplay.PowerState.Actual)) { iRequiredPower = 0; return }
        if (iRequiredInput && (iRequiredInput == uDisplay.Input.Actual)) { iRequiredInput = 0; return }
        //if (iRequiredMute && (iRequiredMute == uDisplay.Volume.Mute.Actual)) { iRequiredMute = 0; return }

        if (iRequiredPower && (iRequiredPower <> uDisplay.PowerState.Actual)) {
        iCommandBusy = true
        SetPower(iRequiredPower)
        iCommandLockOut = true
        switch (iRequiredPower) {
            case REQUIRED_POWER_ON: {
            wait 80 {
                iCommandLockOut = false
                uDisplay.PowerState.Actual = iRequiredPower
            }
            }
            case REQUIRED_POWER_OFF: {
            wait 50 {
                iCommandLockOut = false
                uDisplay.PowerState.Actual = iRequiredPower
            }
            }
        }
        //iPollSequence = GET_POWER
        return
        }

        if (iRequiredInput && (uDisplay.PowerState.Actual == ACTUAL_POWER_ON) && (iRequiredInput <> uDisplay.Input.Actual)) {
        iCommandBusy = true
        SetInput(iRequiredInput)
        iCommandLockOut = true
        wait 20 {
            iCommandLockOut = false
            uDisplay.Input.Actual = iRequiredInput
        }
        //iPollSequence = GET_INPUT
        return
        }

        /*
        if (iRequiredMute && (uDisplay.PowerState.Actual == ACTUAL_POWER_ON) && (iRequiredMute <> uDisplay.Volume.Mute.Actual) && [vdvControl,DEVICE_COMMUNICATING]) {
        iCommandBusy = true
        SetMute(iRequiredMute);
        iCommandLockOut = true
        wait 10 iCommandLockOut = false
        iPollSequence = GET_MUTE;
        return
        }
        */
    }
    }
}

define_function MaintainIPConnection() {
    if (!iIPConnected) {
    NAVClientSocketOpen(dvPort.port,cIPAddress,iTCPPort,IP_TCP)
    }
}

(***********************************************************)
(*                STARTUP CODE GOES BELOW                  *)
(***********************************************************)
DEFINE_START
create_buffer dvPort,cRxBuffer

iModuleEnabled = true

// Update event tables
rebuild_event()
(***********************************************************)
(*                THE EVENTS GO BELOW                      *)
(***********************************************************)
DEFINE_EVENT
data_event[dvPort] {
    online: {
    if (iModuleEnabled && data.device.number <> 0) {
        send_command data.device,"'SET BAUD 9600,N,8,1 485 DISABLE'"
        send_command data.device,"'B9MOFF'"
        send_command data.device,"'CHARD-0'"
        send_command data.device,"'CHARDM-0'"
        send_command data.device,"'HSOFF'"
        timeline_create(TL_DRIVE,ltDrive,length_array(ltDrive),timeline_absolute,timeline_repeat)
    }

    if (iModuleEnabled && data.device.number == 0) {
        iIPConnected = true
        timeline_create(TL_DRIVE,ltDrive,length_array(ltDrive),timeline_absolute,timeline_repeat)
    }
    }
    string: {
    if (iModuleEnabled) {
        iCommunicating = true
        [vdvControl,DATA_INITIALIZED] = true
        TimeOut()
         NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_FROM, dvPort, data.text))
        //if (!iSemaphore) { Process() }
    }
    }
    offline: {
    if (data.device.number == 0) {
        NAVClientSocketClose(dvPort.port)
        iIPConnected = false
        //iCommunicating = false
    }
    }
    onerror: {
    if (data.device.number == 0) {
        //iIPConnected = false
        //iCommunicating = false
    }
    }
}

data_event[vdvControl] {
    command: {
    stack_var char cCmdHeader[NAV_MAX_CHARS]
    stack_var char cCmdParam[3][NAV_MAX_CHARS]
    if (iModuleEnabled) {
        NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_COMMAND_FROM, data.device, data.text))
        cCmdHeader = DuetParseCmdHeader(data.text)
        cCmdParam[1] = DuetParseCmdParam(data.text)
        cCmdParam[2] = DuetParseCmdParam(data.text)
        cCmdParam[3] = DuetParseCmdParam(data.text)
        switch (cCmdHeader) {
        case 'PROPERTY': {
            switch (cCmdParam[1]) {
            case 'IP_ADDRESS': {
                cIPAddress = cCmdParam[2]
                //timeline_create(TL_IP_CHECK,ltIPCheck,length_array(ltIPCheck),timeline_absolute,timeline_repeat)
            }
            case 'TCP_PORT': {
                iTCPPort = atoi(cCmdParam[2])
                timeline_create(TL_IP_CHECK,ltIPCheck,length_array(ltIPCheck),timeline_absolute,timeline_repeat)
            }
            }
        }
        case 'PASSTHRU': { SendString(cCmdParam[1]) }

        case 'POWER': {
            switch (cCmdParam[1]) {
            case 'ON': { iRequiredPower = REQUIRED_POWER_ON; Drive() }
            case 'OFF': { iRequiredPower = REQUIRED_POWER_OFF; iRequiredInput = 0; Drive() }
            }
        }
        case 'VOLUME': {
            switch (cCmdParam[1]) {
            case 'ABS': {
                uDisplay.Volume.Level.Actual = atoi(cCmdParam[2])
                SetVolume(uDisplay.Volume.Level.Actual)
                send_level vdvControl, VOL_LVL, NAVScaleValue(uDisplay.Volume.Level.Actual, (MAX_VOLUME - MIN_VOLUME), 255, 0)
            }
            default: {
                uDisplay.Volume.Level.Actual = NAVScaleValue(atoi(cCmdParam[1]), 255, (MAX_VOLUME - MIN_VOLUME), 0)
                SetVolume(uDisplay.Volume.Level.Actual)
                send_level vdvControl, VOL_LVL, NAVScaleValue(uDisplay.Volume.Level.Actual, (MAX_VOLUME - MIN_VOLUME), 255, 0)
            }
            }
        }
        case 'INPUT': {
            switch (cCmdParam[1]) {
            case 'VGA': {
                switch (cCmdParam[2]) {
                case '1': { iRequiredPower = REQUIRED_POWER_ON; iRequiredInput = REQUIRED_INPUT_PC; Drive() }
                }
            }
            case 'HDMI': {
                switch (cCmdParam[2]) {
                case '1': {
                    iRequiredPower = REQUIRED_POWER_ON; iRequiredInput = REQUIRED_INPUT_HDMI_1; Drive()
                }
                case '2': {
                    iRequiredPower = REQUIRED_POWER_ON; iRequiredInput = REQUIRED_INPUT_HDMI_2; Drive()
                }
                case '3': {
                    iRequiredPower = REQUIRED_POWER_ON; iRequiredInput = REQUIRED_INPUT_HDMI_3; Drive()
                }
                case '4': {
                    iRequiredPower = REQUIRED_POWER_ON; iRequiredInput = REQUIRED_INPUT_HDMI_4; Drive()
                }
                }
            }
            }
        }
        }
    }
    }
}

channel_event[vdvControl,0] {
    on: {
    if (iModuleEnabled) {
        switch (channel.channel) {
        case POWER: {
            if (iRequiredPower) {
            switch (iRequiredPower) {
                case REQUIRED_POWER_ON: { iRequiredPower = REQUIRED_POWER_OFF; iRequiredInput = 0; Drive() }
                case REQUIRED_POWER_OFF: { iRequiredPower = REQUIRED_POWER_ON; Drive() }
            }
            }else {
            switch (uDisplay.PowerState.Actual) {
                case ACTUAL_POWER_ON: { iRequiredPower = REQUIRED_POWER_OFF; iRequiredInput = 0; Drive() }
                case ACTUAL_POWER_OFF: { iRequiredPower = REQUIRED_POWER_ON; Drive() }
            }
            }
        }
        case PWR_ON: { iRequiredPower = REQUIRED_POWER_ON; Drive() }
        case PWR_OFF: { iRequiredPower = REQUIRED_POWER_OFF; iRequiredInput = 0; Drive() }
        //case PIC_MUTE: { SetShutter(![vdvControl,PIC_MUTE_FB]) }
        case VOL_MUTE: {
            if (uDisplay.PowerState.Actual == ACTUAL_POWER_ON) {
            if (iRequiredMute) {
                switch (iRequiredMute) {
                case REQUIRED_MUTE_ON: { iRequiredMute = REQUIRED_MUTE_OFF; Drive() }
                case REQUIRED_MUTE_OFF: { iRequiredMute = REQUIRED_MUTE_ON; Drive() }
                }
            }else {
                switch (uDisplay.Volume.Mute.Actual) {
                case ACTUAL_MUTE_ON: { iRequiredMute = REQUIRED_MUTE_OFF; Drive() }
                case ACTUAL_MUTE_OFF: { iRequiredMute = REQUIRED_MUTE_ON; Drive() }
                }
            }
            }
        }
        }
    }
    }
}

timeline_event[TL_DRIVE] { Drive() }

timeline_event[TL_IP_CHECK] { MaintainIPConnection() }

timeline_event[TL_NAV_FEEDBACK] {
    if (iModuleEnabled) {
    [vdvControl,DEVICE_COMMUNICATING]    = (iCommunicating)
    [vdvControl,VOL_MUTE_FB] = (uDisplay.Volume.Mute.Actual == ACTUAL_MUTE_ON)
    [vdvControl,POWER_FB] = (uDisplay.PowerState.Actual == ACTUAL_POWER_ON)
    //if (iIPConnected) {
        //NAVLog("'Sharp LCD IP Connected'")
    //}
    }
}

(***********************************************************)
(*                     END OF PROGRAM                      *)
(*        DO NOT PUT ANY CODE BELOW THIS COMMENT           *)
(***********************************************************)

