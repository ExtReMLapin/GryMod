// I'm not here to publish the full source code.
// So no, uh you can't compile it with that code only.


var m_data = new Array();
var m_speed = -2;
var m_visibles = new Array();
var m_height = 768;
var m_center = 500;
addName = function (_TextValue, _Style)
{
    var __reg1 = new Object();
    __reg1.Text = _TextValue;
    __reg1.Style = _Style;
    m_data.push(__reg1);
}
;
updateMovement = function ()
{
    var __reg2 = 0;
    while (__reg2 < m_visibles.length) 
    {
        var __reg1 = m_visibles[__reg2];
        var __reg3 = __reg1._y;
        __reg1._y = __reg1._y + m_speed;
        var __reg4 = __reg1._y;
        if (__reg1._y + __reg1._height < -100) 
        {
            m_visibles.splice(__reg2, 1);
            --__reg2;
            __reg1.removeMovieClip();
        }
        else if (__reg1._y > m_height + 200) 
        {
            m_visibles.splice(__reg2, 1);
            --__reg2;
            __reg1.removeMovieClip();
        }
        else if (__reg3 <= m_center && __reg4 > m_center) 
        {
            processCenterEvents(__reg1, -1);
            SendSoundEvents(__reg1, -1);
        }
        else if (__reg3 > m_center && __reg4 <= m_center) 
        {
            processCenterEvents(__reg1, 1);
            SendSoundEvents(__reg1, 1);
        }
        ++__reg2;
    }
    if (m_visibles.length <= 0) 
    {
        var __reg8 = 0;
        var __reg5 = text_normal.duplicateMovieClip("CurObj" + __reg8, __reg8);
        var __reg9 = m_data[__reg8];
        __reg5.Text = __reg9.Text;
        __reg5.Style = __reg9.Style;
        __reg5.ID = __reg8;
        __reg5.gotoAndStop(__reg9.Style + 1);
        __reg5._y = m_height - 200;
        m_visibles.push(__reg5);
        return undefined;
    }
    var __reg7 = m_visibles[0];
    var __reg6 = m_visibles[m_visibles.length - 1];
    if (__reg7._y > -100 && __reg7.ID > 0) 
    {
        __reg8 = __reg7.ID - 1;
        __reg5 = text_normal.duplicateMovieClip("CurObj" + __reg8, __reg8);
        __reg9 = m_data[__reg8];
        __reg5.Text = __reg9.Text;
        __reg5.Style = __reg9.Style;
        __reg5.gotoAndStop(__reg9.Style + 1);
        __reg5._y = __reg7._y - __reg5._height;
        __reg5.ID = __reg8;
        if (__reg9.Style == 3) 
        {
            __reg5.Text3.gotoAndStop(20);
        }
        m_visibles.reverse();
        m_visibles.push(__reg5);
        m_visibles.reverse();
    }
    if (__reg6._y + __reg6._height < m_height + 100 && __reg6.ID < m_data.length - 1) 
    {
        __reg8 = __reg6.ID + 1;
        __reg5 = text_normal.duplicateMovieClip("CurObj" + __reg8, __reg8);
        __reg9 = m_data[__reg8];
        __reg5.Text = __reg9.Text;
        __reg5.Style = __reg9.Style;
        __reg5.ID = __reg8;
        __reg5.gotoAndStop(__reg9.Style + 1);
        __reg5._y = __reg6._y + __reg6._height;
        m_visibles.push(__reg5);
    }
}
;
onEnterFrame = updateMovement;
getURL("FSCommand:credits_start", "");
processCenterEvents = function (obj, dir)
{
    if (dir == 1) 
    {
        if (obj.Style == 3) 
        {
            obj.Text3.gotoAndPlay("play");
        }
        return;
    }
    if (dir == -1) 
    {
        if (obj.Style == 3) 
        {
            obj.Text3.gotoAndStop("off");
        }
    }
}
;
var m_soundEvent = new Array();
m_soundEvent["@CrytekExecutiveManagement"] = "1";
m_soundEvent["@ResearchDevelopment"] = "2";
m_soundEvent["@GameProgramming"] = "3";
m_soundEvent["@GameDesign"] = "4";
m_soundEvent["@AdditionalGameDesign"] = "4b";
m_soundEvent["@Art"] = "5";
m_soundEvent["@Animation"] = "6";
m_soundEvent["@QA2"] = "6b";
m_soundEvent["@PerformanceConsultingSupport"] = "7";
m_soundEvent["@AdditionalSoundDesign"] = "9";
m_soundEvent["@AdditionalEmployeesofCrytekFamilieinFrankfurtBudapestandKiev1"] = "10";
m_soundEvent["@SpecialThanksto"] = "11";
m_soundEvent["@FromtheCrytekTeam"] = "12";
m_soundEvent["@ThirdPartySoftwareandTools"] = "13";
m_soundEvent["@EACREDITS"] = "14";
m_soundEvent["@MT_AsiaPacificMarketing"] = "14b";
m_soundEvent["@MT_ThailandMarketing"] = "14c";
m_soundEvent["@Localisation"] = "15";
m_soundEvent["@QA"] = "16";
m_soundEvent["@ComplianceLeads"] = "17";
m_soundEvent["@EALAMasteringLab"] = "17b";
m_soundEvent["@TechnicalComplianceGroup"] = "18";
m_soundEvent["@ECGGameplayDivision"] = "18b";
m_soundEvent["@ECGNetworkDivision"] = "18c";
m_soundEvent["@ECGSubmissionsDivision"] = "19";
m_soundEvent["@VoiceTalent"] = "19b";
m_soundEvent["@SpecialThanks"] = "20";
SendSoundEvents = function (obj, dir)
{
    if (dir == 1) 
    {
        obj.Style != 3;
    }
    else if (dir == -1) 
    {
        obj.Style != 3;
    }
    var __reg1 = m_soundEvent[obj.Text];
    if (__reg1 != undefined) 
    {
        getURL("FSCommand:" + ("credit_group" + __reg1), "");
    }
}
;
prepareData = function ()
{

    addName("", 0);
    addName("", 0);
    addName("GryMod Project", 3);
    addName("", 5);
    addName("Lead Dev", 1);
    addName("Pierre 'Lapin' Leet", 2);
    addName("", 0);
    addName("3D Artist", 1);
    addName("Carl 'carlmcgee' Mcgee", 2);
    addName("", 0);
    addName("2D Artists", 1);
    addName("Vuthakral Darastrix", 2);
    addName("Pierre 'Lapin' Leet", 2);
    addName("", 0);
    addName("", 0);
    addName("", 0);
    addName("Concepts", 3);
    addName("", 5);
    addName("Quick Menu Concept", 2);
    addName("Dlaor", 1);
    addName("Crysis Hands", 2);
    addName("Carl 'carlmcgee' Mcgee", 1);

    addName("", 0);
    addName("Used Softwares", 2);
    addName("Adobe Flash Pro", 1);
    addName("Notepad++", 1);
    addName("Scaleform GFx", 1);
    addName("Some Reverse-Engineering tools", 1);
    addName("", 0);
    addName("", 0);
    addName("", 0);
    addName("", 0);
    addName("Support & Thanks (More important than it seems)", 3);
    addName("", 5);
    addName("Ideas", 1);
    addName("Vuthakral Darastrix", 2);
    addName("", 0);
    addName("Help on the HTML part", 1);
    addName("Adobe Community", 2);
    addName("", 0);
    addName("Ideas", 1);
    addName("Steam Community", 2);
    addName("", 0);
    addName("Spamming me on Steam", 1);
    addName("Steam Kids", 2);
    addName("", 0);
    addName("", 0);
    addName("", 0);
    addName("", 5);

    addName("CryTek Staff", 3);
    addName("Because all of them worked on Crysis 1 Interface", 1);
    addName("", 0);
    addName("2D Artist", 1);
    addName("Pino Gengo", 2);
    addName("Marco Siegel", 2);
    addName("", 0);
    addName("Flash Artist", 1);
    addName("Karsten Klewer", 2);
    addName("", 0);
    addName("Senior SFX Artist", 1);
    addName("Sean Ellis", 2);
    addName("", 0);
    addName("SFX Artist", 1);
    addName("Taku Wanifuchi", 2);
    addName("", 0);
    addName("Concept Artist", 1);
    addName("T.J. Frame", 2);
    addName("Edward Lee", 2);
    addName("Ray Leung", 2);
    addName("Jean-Sebastien Rohlion", 2);
    addName("UI Artist", 1);
    addName("Sven Dixon", 2);
    addName("Thanks Sven ! You did a great job", 3);
    addName("", 0);
    addName("", 0);
    addName("", 0);
    addName("Special Thanks", 3);
    addName("", 5);
    addName("Facepunch Community", 2);
    addName("You, for using GryMod !", 2);
    addName("", 0);
    addName("", 0);
    addName("", 0);
    addName("Because it's where are Lazy devs", 3);
	addName("", 6); // ExtReM Team logo
}
prepareData();
