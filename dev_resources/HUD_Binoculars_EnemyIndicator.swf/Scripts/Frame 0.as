//Frame 0
//  Action tag #0

_root.Line._visible = false;
_root.Over._visible = false;
_root.Text._visible = false;
var Line_color = new Color(Line.Colorset);
var Over_color = new Color(Over.Colorset);
var Text_color = new Color(Text.Colorset);
setLineColor = function (_strLine)
{
    Line_color.setRGB(_strLine);
}
;
setOverColor = function (_strOver)
{
    Over_color.setRGB(_strOver);
}
;
setTextColor = function (_strText)
{
    Text_color.setRGB(_strText);
}
;
var m_allValues = new Array();
var m_allIcons = new Array();
var m_curLockingID = 0;
updateLockBrackets = function ()
{
    var __reg2 = new Number();
    var __reg6 = new Number();
    __reg6 = 0;
    var __reg13 = _root.Root.CornerBottomRight._width * 0.5;
    var __reg12 = _root.Root.CornerBottomRight._height * 0.5;
    __reg2 = 0;
    while (__reg2 < m_allValues.length) 
    {
        var __reg9 = m_allValues[__reg2];
        var __reg3 = m_allIcons[__reg6];
        if (!__reg3) 
        {
            __reg3 = _root.Root.duplicateMovieClip("Object_" + __reg6, __reg6 + 100);
            m_allIcons[__reg6] = __reg3;
        }
        if (!__reg3) 
        {
            return undefined;
        }
        var __reg7 = m_allValues[__reg2 + 11];
        var __reg8 = m_allValues[__reg2 + 12];
        __reg3._visible = __reg7;
        __reg3.objID = __reg9;
        if (__reg7) 
        {
            var __reg5 = m_allValues[__reg2 + 3] - m_allValues[__reg2 + 1];
            if (__reg5 < 55) 
            {
                m_allValues[__reg2 + 1] = m_allValues[__reg2 + 1] - (55 - __reg5) / 2;
                m_allValues[__reg2 + 5] = m_allValues[__reg2 + 5] - (55 - __reg5) / 2;
                m_allValues[__reg2 + 3] = m_allValues[__reg2 + 3] + (55 - __reg5) / 2;
                m_allValues[__reg2 + 7] = m_allValues[__reg2 + 7] + (55 - __reg5) / 2;
            }
            var __reg4 = m_allValues[__reg2 + 6] - m_allValues[__reg2 + 2];
            if (__reg4 < 61) 
            {
                m_allValues[__reg2 + 2] = m_allValues[__reg2 + 2] - (61 - __reg4) / 2;
                m_allValues[__reg2 + 4] = m_allValues[__reg2 + 4] - (61 - __reg4) / 2;
                m_allValues[__reg2 + 6] = m_allValues[__reg2 + 6] + (61 - __reg4) / 2;
                m_allValues[__reg2 + 8] = m_allValues[__reg2 + 8] + (61 - __reg4) / 2;
            }
            __reg3.CornerTopLeft._x = m_allValues[__reg2 + 1];
            __reg3.CornerTopLeft._y = m_allValues[__reg2 + 2];
            __reg3.CornerTopRight._x = m_allValues[__reg2 + 3];
            __reg3.CornerTopRight._y = m_allValues[__reg2 + 4];
            __reg3.CornerBottomLeft._x = m_allValues[__reg2 + 5];
            __reg3.CornerBottomLeft._y = m_allValues[__reg2 + 6];
            __reg3.CornerBottomRight._x = m_allValues[__reg2 + 7];
            __reg3.CornerBottomRight._y = m_allValues[__reg2 + 8];
            __reg3.TargetLockText._x = m_allValues[__reg2 + 9];
            __reg3.TargetLockText._y = m_allValues[__reg2 + 10];
            var __reg11 = m_allValues[__reg2 + 7] + 2;
            var __reg10 = m_allValues[__reg2 + 1] + 2;
            if (__reg8) 
            {
                __reg3.CornerTopLeft.gotoAndStop("locked");
                __reg3.CornerTopRight.gotoAndStop("locked");
                __reg3.CornerBottomLeft.gotoAndStop("locked");
                __reg3.CornerBottomRight.gotoAndStop("locked");
            }
            else 
            {
                __reg3.CornerTopLeft.gotoAndStop(1);
                __reg3.CornerTopRight.gotoAndStop(1);
                __reg3.CornerBottomLeft.gotoAndStop(1);
                __reg3.CornerBottomRight.gotoAndStop(1);
            }
        }
        ++__reg6;
        __reg2 = __reg2 + 12;
        ++__reg2;
    }
    if (__reg6 <= m_allIcons.length) 
    {
        __reg2 = __reg6;
        while (__reg2 < m_allIcons.length) 
        {
            m_allIcons[__reg2]._visible = false;
            ++__reg2;
        }
    }
    m_allValues.splice(0);
    _root.Root._visible = false;
}
;
setLineColor(5599800);
setOverColor(7915313);
setTextColor(5599800);

