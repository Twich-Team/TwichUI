-- Temporary addon only. Registration does not run tests or schedule work.
local addon, P = ...
local function say(s) if type(print)=='function' then print(s) end end
local function clockAPI()
    if type(GetTimePreciseSec)=='function' then return GetTimePreciseSec,'GetTimePreciseSec' end
    if type(debugprofilestop)=='function' then return function()return debugprofilestop()/1000 end,'debugprofilestop (never reset)' end
    if type(GetTime)=='function' then return GetTime,'GetTime (coarse resolution)' end
    return nil,'unavailable'
end
local function api()
    local clock,name=clockAPI()
    local build='unavailable'
    if type(GetBuildInfo)=='function' then
        local ok,version,number,date,interface=pcall(GetBuildInfo)
        if ok then build=table.concat({tostring(version),tostring(number),tostring(date),tostring(interface)},' / ') end
    end
    return {clock=clock,clockName=name,build=build,
        heap=type(collectgarbage)=='function' and function()return collectgarbage('count') end or nil,
        inCombat=type(InCombatLockdown)=='function' and InCombatLockdown or nil,
        decode=C_EncodingUtil and C_EncodingUtil.DecodeBase64,
        inflate=C_EncodingUtil and C_EncodingUtil.DecompressString,
        method=Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate}
end
local function cancel(reason)
    if P.timer then P.timer:Cancel();P.timer=nil end
    if P.run and not P.run.done then P.run:Cancel(reason);P.report=P.run:Report() end
end
local function window()
    if P.frame then return P.frame end
    local f=CreateFrame('Frame','TwichUICodecProbeReport',UIParent,'BackdropTemplate')
    f:SetSize(700,470);f:SetPoint('CENTER');f:SetFrameStrata('DIALOG');f:SetClampedToScreen(true)
    if f.SetDontSavePosition then f:SetDontSavePosition(true) end
    f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
    f:SetBackdropColor(.07,.05,.035,.98);f:SetBackdropBorderColor(.58,.43,.25,1)
    local title=f:CreateFontString(nil,'OVERLAY','GameFontNormalLarge')
    title:SetPoint('TOPLEFT',16,-15);title:SetText('Forever codec probe — DEV ONLY');title:SetTextColor(.91,.86,.73)
    local status=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    status:SetPoint('TOPLEFT',16,-42);status:SetWidth(645);status:SetJustifyH('LEFT')
    local scroll=CreateFrame('ScrollFrame',nil,f,'UIPanelScrollFrameTemplate')
    scroll:SetPoint('TOPLEFT',16,-76);scroll:SetPoint('BOTTOMRIGHT',-36,48)
    local edit=CreateFrame('EditBox',nil,scroll)
    edit:SetWidth(640);edit:SetMultiLine(true);edit:SetAutoFocus(false);edit:SetMaxLetters(24000)
    edit:SetFontObject('ChatFontNormal');edit:SetTextInsets(4,4,4,4)
    edit:SetScript('OnEscapePressed',function()f:Hide()end)
    edit:SetScript('OnTextChanged',function(e,user)
        if user and P.report then e:SetText(P.report);e:HighlightText() end
    end)
    scroll:SetScrollChild(edit)
    local copy=CreateFrame('Button',nil,f,'UIPanelButtonTemplate')
    copy:SetSize(150,24);copy:SetPoint('BOTTOMLEFT',16,13);copy:SetText('Select report')
    copy:SetScript('OnClick',function()edit:SetFocus();edit:HighlightText()end)
    local note=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    note:SetPoint('LEFT',copy,'RIGHT',12,0);note:SetText('Ctrl+C to copy. Escape closes/cancels.')
    local close=CreateFrame('Button',nil,f,'UIPanelCloseButton')
    close:SetPoint('TOPRIGHT',-2,-2);close:SetScript('OnClick',function()f:Hide()end)
    f:SetScript('OnHide',function()cancel('cancelled: report window hidden')end)
    f.status=status;f.edit=edit;P.frame=f
    if type(UISpecialFrames)=='table' then UISpecialFrames[#UISpecialFrames+1]='TwichUICodecProbeReport' end
    f:Hide()
    return f
end
local function finish()
    local f=P.frame
    P.report=P.run:Report()
    f.status:SetText(P.run:Summary())
    f.edit:SetText(P.report);f.edit:SetFocus();f.edit:HighlightText()
    say(P.run:Summary())
    say(('Largest exact output: %d bytes. Worst decompression: %s. Copy the open report.'):format(P.run.largestExact,P.run.timed>0 and ('%.3f ms'):format(P.run.worst) or 'unavailable'))
end
local function schedule(run)
    P.timer=C_Timer.NewTimer(.05,function()
        P.timer=nil
        if P.run~=run or run.done or not P.frame:IsShown() then return end
        local ok,done=pcall(run.Step,run)
        if not ok then
            run.rows[#run.rows+1]={id='probe-error',status='FAILED',reason=tostring(done):sub(1,240)}
            run:Cancel('probe error contained');done=true
        end
        P.frame.status:SetText(('Testing %d/%d — close to cancel'):format(run.index,#run.queue))
        if done then finish() else schedule(run) end
    end)
end
function P.Start()
    local f=window();f:Show()
    if P.run and not P.run.done then return end
    P.run=P.NewRun(api());P.report='Running bounded synthetic tests. Close this window to cancel.'
    f.edit:SetText(P.report);f.status:SetText('Starting codec tests…')
    if not(C_Timer and type(C_Timer.NewTimer)=='function') then
        P.run:Cancel('C_Timer.NewTimer missing; synchronous test loop deliberately not used');finish()
    else schedule(P.run) end
end
local function command(msg)
    msg=(msg or ''):lower():match('^%s*(.-)%s*$')
    if msg=='' or msg=='codecprobe' then P.Start()
    elseif msg=='show' or msg=='codecprobe show' then
        local f=window();f:Show();f.status:SetText(P.run and P.run:Summary() or 'Not run')
        f.edit:SetText(P.report or 'Run /tui codecprobe first.');f.edit:SetFocus();f.edit:HighlightText()
    else say('Use /tui codecprobe (or standalone /tuicodecprobe).') end
end
-- Standalone alias is always available. The optional wrapper delegates every
-- non-probe command and exists only while this removable addon is installed.
SLASH_TWICHUICPROBE1='/tuicodecprobe'
SlashCmdList.TWICHUICPROBE=command
local previous=SlashCmdList.TWICHUI
if type(previous)=='function' then
    SlashCmdList.TWICHUI=function(msg,...)
        local text=(msg or ''):lower():match('^%s*(.-)%s*$')
        if text=='codecprobe' or text=='codecprobe show' then return command(text) end
        return previous(msg,...)
    end
elseif not SLASH_TWICHUI1 and not SLASH_TWICHUI2 then
    local occupied=false
    for key,value in pairs(_G) do
        if type(key)=='string' and key:match('^SLASH_') and type(value)=='string' and value:lower()=='/tui' then occupied=true;break end
    end
    if not occupied then SLASH_TWICHUICPROBE2='/tui' end
end
