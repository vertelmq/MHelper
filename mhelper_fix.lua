local samp = require 'lib.samp.events'
local imgui = require 'mimgui'
local encoding = require 'encoding'
local inicfg = require 'inicfg'
local ffi = require 'ffi'

encoding.default = 'CP1251'
local u8 = encoding.UTF8

local URL_VERSION_MANIFEST = "https://raw.githubusercontent.com/vertelmq/MHelper/refs/heads/main/version.json"
local CURRENT_VERSION = "1.6.0"

local direct_ini = "moonloader//config//mhelper_config.ini"
local log_path = "moonloader//config//mhelper_levers.log"

local ini_data = inicfg.load({
    settings = {
        miranda_delay = 1500,
        fraction = 0,
        fsb_callsign = "",
        fsb_rank = "",
        mvd_callsign = "",
        mvd_rank = "",
        hide_ad = false,
        hide_vr = false
    }
}, direct_ini)
if not doesFileExist(direct_ini) then inicfg.save(ini_data, direct_ini) end

local win_state = imgui.new.bool(false)
local active_tab = 1
local saved_id = nil
local saved_name = "Unknown" 
local is_processing = false 
local miranda_thread = nil 

local alpha = 0.0

local font_normal = nil
local font_bold = nil

local imgui_delay = imgui.new.int(ini_data.settings.miranda_delay)

local state_hide_ad = imgui.new.bool(ini_data.settings.hide_ad)
local state_hide_vr = imgui.new.bool(ini_data.settings.hide_vr)

local buf_fsb_callsign = imgui.new.char[128](u8(ini_data.settings.fsb_callsign))
local buf_fsb_rank = imgui.new.char[128](u8(ini_data.settings.fsb_rank))
local buf_mvd_callsign = imgui.new.char[128](u8(ini_data.settings.mvd_callsign))
local buf_mvd_rank = imgui.new.char[128](u8(ini_data.settings.mvd_rank))

local quit_reasons = {
    [0] = "Таймаут / Краш",
    [1] = "Выход (/q)",
    [2] = "Кик / Бан"
}

local reset_commands = {
    ["uncuff"] = true,
    ["arrest"] = true,
}

imgui.OnInitialize(function()
    local style = imgui.GetStyle()
    local colors = style.Colors
    local io = imgui.GetIO()
    
    local font_path_normal = "C:\\Windows\\Fonts\\trebuc.ttf"   
    local font_path_bold = "C:\\Windows\\Fonts\\trebucbd.ttf"   
    
    if doesFileExist(font_path_normal) then
        font_normal = io.Fonts:AddFontFromFileTTF(font_path_normal, 14.0, nil, io.Fonts:GetGlyphRangesCyrillic())
    end
    if doesFileExist(font_path_bold) then
        font_bold = io.Fonts:AddFontFromFileTTF(font_path_bold, 16.0, nil, io.Fonts:GetGlyphRangesCyrillic())
    end
    
    style.WindowRounding = 12.0
    style.FrameRounding = 6.0
    style.ChildRounding = 8.0
    style.PopupRounding = 6.0
    style.ScrollbarSize = 8.0
    style.ScrollbarRounding = 12.0
    style.ItemSpacing = imgui.ImVec2(12, 8)
    style.WindowPadding = imgui.ImVec2(15, 15)
    
    colors[imgui.Col.WindowBg] = imgui.ImVec4(0.07, 0.07, 0.09, 0.96)
    colors[imgui.Col.ChildBg] = imgui.ImVec4(0.11, 0.11, 0.14, 0.50)
    colors[imgui.Col.Border] = imgui.ImVec4(0.18, 0.18, 0.22, 1.00)
    colors[imgui.Col.BorderShadow] = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
    
    colors[imgui.Col.FrameBg] = imgui.ImVec4(0.13, 0.13, 0.16, 1.00)
    colors[imgui.Col.FrameBgHovered] = imgui.ImVec4(0.18, 0.18, 0.22, 1.00)
    colors[imgui.Col.FrameBgActive] = imgui.ImVec4(0.22, 0.22, 0.26, 1.00)
    
    colors[imgui.Col.TitleBg] = imgui.ImVec4(0.07, 0.07, 0.09, 1.00)
    colors[imgui.Col.TitleBgActive] = imgui.ImVec4(0.11, 0.11, 0.14, 1.00)
    
    colors[imgui.Col.Button] = imgui.ImVec4(0.14, 0.14, 0.17, 1.00)
    colors[imgui.Col.ButtonHovered] = imgui.ImVec4(0.22, 0.22, 0.27, 1.00)
    colors[imgui.Col.ButtonActive] = imgui.ImVec4(0.11, 0.11, 0.14, 1.00)
    
    colors[imgui.Col.Text] = imgui.ImVec4(0.95, 0.96, 0.98, 1.00)
    colors[imgui.Col.TextDisabled] = imgui.ImVec4(0.50, 0.52, 0.55, 1.00)
    
    colors[imgui.Col.Header] = imgui.ImVec4(0.85, 0.24, 0.24, 0.30)
    colors[imgui.Col.HeaderHovered] = imgui.ImVec4(0.85, 0.24, 0.24, 0.70)
    colors[imgui.Col.HeaderActive] = imgui.ImVec4(0.65, 0.18, 0.18, 1.00)
    
    colors[imgui.Col.SliderGrab] = imgui.ImVec4(0.85, 0.24, 0.24, 1.00)
    colors[imgui.Col.SliderGrabActive] = imgui.ImVec4(0.95, 0.35, 0.35, 1.00)
    colors[imgui.Col.CheckMark] = imgui.ImVec4(0.85, 0.24, 0.24, 1.00)
end)

function isGameReady()
    return not sampIsChatInputActive() and not sampIsDialogActive() and not isPauseMenuActive()
end

function isSelfAlive()
    local _, self_id = sampGetPlayerIdByCharHandle(PLAYER_HANDLE)
    if self_id and sampIsPlayerConnected(self_id) then
        return sampGetPlayerHealth(self_id) > 0
    end
    return true
end

function checkFactionSelected()
    if ini_data.settings.fraction == 0 then
        sampAddChatMessage("{FF6347}[MHelper]{FFFFFF} Ошибка! Сначала выберите вашу фракцию в меню {FFFF00}/mhelp", -1)
        return false
    end
    return true
end

function getTargetPlayerId()
    local res, ped = getCharPlayerIsTargeting(PLAYER_HANDLE)
    if res and doesCharExist(ped) then
        local is_player, id = sampGetPlayerIdByCharHandle(ped)
        if is_player and sampIsPlayerConnected(id) then
            return id
        end
    end

    local nearest_id = nil
    local min_dist = 30.0 
    
    local _, self_id = sampGetPlayerIdByCharHandle(PLAYER_HANDLE)
    if not self_id or not sampIsPlayerConnected(self_id) then return nil end
    
    local res_my, my_x, my_y, my_z = sampGetPlayerPos(self_id)
    if not res_my then return nil end

    for id = 0, 1003 do
        if sampIsPlayerConnected(id) and id ~= self_id then
            local has_handle, target_ped = sampGetCharHandleBySampPlayerId(id)
            if has_handle and doesCharExist(target_ped) then
                local res_target, tx, ty, tz = sampGetPlayerPos(id)
                if res_target then
                    local dist = math.sqrt((tx - my_x)^2 + (ty - my_y)^2 + (tz - my_z)^2)
                    if dist < min_dist then
                        min_dist = dist
                        nearest_id = id
                    end
                end
            end
        end
    end
    return nearest_id
end

function writeLog(text)
    local file = io.open(log_path, "a")
    if file then
        file:write(text .. "\n")
        file:close()
    end
end

function makeGameScreenshot()
    setVirtualKeyDown(119, true) 
    lua_thread.create(function()
        wait(50)
        setVirtualKeyDown(119, false) 
    end)
end

function readMiranda(id)
    if not checkFactionSelected() then return end

    id = tonumber(id)
    if not id or not sampIsPlayerConnected(id) then return end

    if miranda_thread and miranda_thread:status() ~= "dead" then
        sampAddChatMessage("{FF6347}[MHelper]{FFFFFF} Миранда уже зачитывается.", -1)
        return
    end

    local name = sampGetPlayerNickname(id)
    if not name then return end
    name = name:gsub('_', ' ')

    miranda_thread = lua_thread.create(function()
        local delay = ini_data.settings.miranda_delay
        
        if ini_data.settings.fraction == 1 then
            sampSendChat("Вы задержаны Территориальным Управлением Федеральной службы безопасности НО.")
        elseif ini_data.settings.fraction == 2 then
            sampSendChat("Вы задержаны Министерством внутренних дел НО.")
        end
        
        wait(delay)
        if not isSelfAlive() or not sampIsPlayerConnected(id) then return end
        
        sampSendChat("Поясняю Ваши права:")
        wait(delay)

        local lines = {
            "Вы имеете право хранить молчание. Всё, что Вы скажете, может быть использовано против Вас.",
            "Если Вы решите давать показания, они могут быть использованы в качестве доказательств.",
            "Вы имеете право на помощь защитника после доставления в КПЗ  государственного или частного.",
            "Вы имеете право знакомиться с материалами уголовного дела и процессуальными документами.",
            "Вы имеете право обжаловать действия или бездействие участников уголовного процесса.",
            "Вам ясны Ваши права?"
        }

        for _, text in ipairs(lines) do
            if not isSelfAlive() or not sampIsPlayerConnected(id) then 
                sampAddChatMessage("{FF6347}[MHelper]{FFFFFF} Чтение Миранды прервано (цель покинула сервер или мертва).", -1)
                break 
            end
            sampSendChat(text)
            wait(delay)
        end
    end)
end

function samp.onPlayerQuit(playerId, reason)
    if saved_id and playerId == saved_id then
        local reason_text = quit_reasons[reason] or "Неизвестно"
        local timestamp = os.date("[%d.%m.%Y | %H:%M:%S]")
        
        sampAddChatMessage("{FF3333}[MHelper] ВНИМАНИЕ! ЦЕЛЬ ВЫШЛА ИЗ ИГРЫ!{FFFFFF}", -1)
        sampAddChatMessage(string.format("{FF3333}[MHelper]{FFFFFF} Игрок: {FFFF00}%s [%d]{FFFFFF} | Причина: {FF6347}%s{FFFFFF}", saved_name, playerId, reason_text), -1)
        
        local log_entry = string.format("%s Игрок: %s [%d] вышел с сервера. Причина: %s", timestamp, saved_name, playerId, reason_text)
        writeLog(log_entry)

        local has_handle, target_ped = sampGetCharHandleBySampPlayerId(playerId)
        if has_handle and doesCharExist(target_ped) then
            deleteChar(target_ped)
        end

        lua_thread.create(function()
            sampSendChat("/time")
            wait(350)
            makeGameScreenshot()
            sampAddChatMessage("{33CCFF}[MHelper]{FFFFFF} Скриншот сделан через F8 и лог сохранен!", -1)
        end)
        
        saved_id = nil
        saved_name = "Unknown"
    end
end

function samp.onSendCommand(command)
    local cmd, args = command:match("^/([^%s]+)%s*(.*)$")
    if cmd then
        if saved_id and reset_commands[cmd] then
            local target_id = args:match("(%d+)")
            target_id = tonumber(target_id)
            
            if not target_id or target_id == saved_id then
                sampAddChatMessage(string.format("{33CCFF}[MHelper]{FFFFFF} Взаимодействие с игроком {FFFF00}%s [%d]{FFFFFF} завершено через команду. Цель сброшена.", saved_name, saved_id), -1)
                saved_id = nil
                saved_name = "Unknown"
            end
        end
    end
end

-- НАДЁЖНАЯ СИСТЕМА ОБНОВЛЕНИЯ ЧЕРЕЗ УНИКАЛЬНЫЕ ВРЕМЕННЫЕ ФАЙЛЫ
function checkUpdates(is_manual)
    lua_thread.create(function()
        if not is_manual then 
            wait(7000) -- Даём игре полностью прогрузиться, чтобы не спамить в пустой чат
        end
        
        sampAddChatMessage("{853D3D}[MHelper]{FFFFFF} Проверка обновлений...", -1)
        
        -- Генерируем уникальное имя файла для манифеста, чтобы избежать конфликтов блокировки
        local tmp_manifest = os.getenv('TEMP') .. '\\mh_manifest_' .. os.time() .. '.json'
        
        downloadUrlToFile(URL_VERSION_MANIFEST, tmp_manifest, function(id, status, p1, p2)
            if status == 6 then -- Загрузка завершена успешно
                local f = io.open(tmp_manifest, "r")
                if f then
                    local content = f:read("*a")
                    f:close()
                    os.remove(tmp_manifest) -- Сразу удаляем за собой временный файл
                    
                    local latest_version = content:match('"latest_version"%s*:%s*"([^"]+)"')
                    local download_url = content:match('"download_url"%s*:%s*"([^"]+)"')
                    
                    if latest_version and download_url then
                        if latest_version ~= CURRENT_VERSION then
                            sampAddChatMessage(string.format("{853D3D}[MHelper]{FFFFFF} Найдена новая версия: {FFFF00}%s{FFFFFF}! Скачивание...", latest_version), -1)
                            downloadNewVersion(download_url)
                        else
                            sampAddChatMessage("{853D3D}[MHelper]{FFFFFF} У вас установлена актуальная версия скрипта.", -1)
                        end
                    else
                        sampAddChatMessage("{FF6347}[MHelper] Ошибка обновления: Неверная структура манифеста сервера.", -1)
                    end
                end
            elseif status == -1 then
                sampAddChatMessage("{FF6347}[MHelper] Не удалось проверить обновления (Ошибка соединения).", -1)
            end
        end)
    end)
end

function downloadNewVersion(url)
    local script_path = thisScript().path
    -- Генерируем полностью уникальное имя для файла обновления
    local update_tmp_path = os.getenv('TEMP') .. '\\mh_update_' .. os.time() .. '.tmp'

    downloadUrlToFile(url, update_tmp_path, function(id, status, p1, p2)
        if status == 6 then
            local f = io.open(update_tmp_path, "rb")
            if f then
                local content = f:read("*a")
                f:close()
                
                -- Базовая валидация структуры файла, чтобы не сломать скрипт
                if content:len() > 100 and (content:sub(1, 4) == "\27Lua" or content:sub(1, 5) == "local" or content:sub(1, 2) == "--") then
                    sampAddChatMessage("{33CCFF}[MHelper]{FFFFFF} Обновление успешно загружено. Перезаписываем файл...", -1)
                    
                    lua_thread.create(function()
                        wait(500)
                        
                        -- Безопасное удаление старого файла перед установкой нового
                        os.remove(script_path)
                        local success, err = os.rename(update_tmp_path, script_path)
                        
                        if not success then
                            -- Резервный вариант, если переименование зажато процессами лаунчера
                            local fallback = io.open(script_path, "wb")
                            if fallback then
                                fallback:write(content)
                                fallback:close()
                                os.remove(update_tmp_path)
                                success = true
                            end
                        end
                        
                        if success then
                            sampAddChatMessage("{33CCFF}[MHelper]{FFFFFF} Скрипт успешно обновлен! Перезапуск...", -1)
                            wait(500)
                            thisScript():reload() -- Перезапускаем скрипт
                        else
                            sampAddChatMessage("{FF6347}[MHelper] Ошибка замены файла. Пожалуйста, запустите лаунчер от Администратора.", -1)
                        end
                    end)
                else
                    os.remove(update_tmp_path)
                    sampAddChatMessage("{FF6347}[MHelper] Ошибка: Файл на сервере поврежден или пуст.", -1)
                end
            end
        elseif status == -1 then
            sampAddChatMessage("{FF6347}[MHelper] Сбой при скачивании файла обновления.", -1)
        end
    end)
end

imgui.OnFrame(
    function() 
        if win_state[0] then
            if alpha < 1.0 then alpha = alpha + 0.08 end
            if alpha > 1.0 then alpha = 1.0 end
        else
            if alpha > 0.0 then alpha = alpha - 0.08 end
            if alpha < 0.0 then alpha = 0.0 end
        end
        return alpha > 0.0 
    end,
    function()
        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, alpha)
        if font_normal then imgui.PushFont(font_normal) end

        local screen_x, screen_y = getScreenResolution()
        imgui.SetNextWindowPos(imgui.ImVec2(screen_x / 2, screen_y / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(670, 460), imgui.Cond.FirstUseEver)

        imgui.Begin(u8"Markelow Tools | t.me/vestellworld", win_state, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)

        imgui.BeginChild("Tabs", imgui.ImVec2(170, 0), true)
        imgui.Spacing()
        
        local function DrawMenuTab(id, label)
            if active_tab == id then
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.85, 0.24, 0.24, 1.00))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.95, 0.30, 0.30, 1.00))
                imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.70, 0.18, 0.18, 1.00))
            else
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.14, 0.14, 0.17, 1.00))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.20, 0.25, 1.00))
                imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.11, 0.11, 0.14, 1.00))
            end
            if imgui.Button(u8(label), imgui.ImVec2(-1, 38)) then active_tab = id end
            imgui.PopStyleColor(3)
            imgui.Spacing()
        end

        DrawMenuTab(1, "Главная")
        DrawMenuTab(2, "Настройки фракции")
        DrawMenuTab(3, "Помощь")
        
        imgui.EndChild()

        imgui.SameLine()

        imgui.BeginChild("Content", imgui.ImVec2(0, 0), true)
        
        if active_tab == 1 then
            imgui.TextColored(imgui.ImVec4(0.95, 0.30, 0.30, 1.00), u8"ОСНОВНАЯ ИНФОРМАЦИЯ")
            imgui.Separator()
            imgui.TextDisabled(u8"Разработчики: Kurama Markelow & Alexander Markelow")
            imgui.TextDisabled(u8(string.format("Версия: %s", CURRENT_VERSION)))
            
            if imgui.Button(u8"Проверить обновление", imgui.ImVec2(180, 26)) then
                checkUpdates(true)
            end
            
            imgui.Spacing()
            
            imgui.TextColored(imgui.ImVec4(0.30, 0.85, 0.40, 1.00), u8"ТЕКУЩИЙ СТАТУС")
            imgui.Separator()
            if saved_id then
                imgui.Text(u8(string.format("Приоритетный ID: %d (%s)", saved_id, saved_name)))
                imgui.SameLine()
                if imgui.Button(u8"Сбросить цель", imgui.ImVec2(120, 24)) then 
                    sampAddChatMessage(string.format("{33CCFF}[MHelper]{FFFFFF} Приоритетная цель {FFFF00}%s [%d]{FFFFFF} успешно сброшена.", saved_name, saved_id), -1)
                    saved_id = nil 
                    saved_name = "Unknown"
                end
            else
                imgui.Text(u8"Приоритетный ID: Автопоиск (Прицел / Ближайший)")
            end
            
            imgui.Spacing()
            imgui.TextColored(imgui.ImVec4(0.95, 0.70, 0.20, 1.00), u8"ФИЛЬТРАЦИЯ ЧАТА (РАДИОЭЛЕКТРОННАЯ БОРЬБА)")
            imgui.Separator()
            
            if imgui.Checkbox(u8"Глушить объявления прессы (/ad) [В разработке]", state_hide_ad) then
                ini_data.settings.hide_ad = state_hide_ad[0]
                inicfg.save(ini_data, direct_ini)
            end
            if imgui.Checkbox(u8"Глушить VIP-чат (/vr) [В разработке]", state_hide_vr) then
                ini_data.settings.hide_vr = state_hide_vr[0]
                inicfg.save(ini_data, direct_ini)
            end

            imgui.Spacing()
            imgui.TextColored(imgui.ImVec4(0.95, 0.70, 0.20, 1.00), u8"КОНФИГУРАЦИЯ")
            imgui.Separator()
            
            imgui.PushItemWidth(200)
            if imgui.SliderInt(u8"Задержка чата (мс)", imgui_delay, 1000, 4000) then
                ini_data.settings.miranda_delay = imgui_delay[0]
                inicfg.save(ini_data, direct_ini)
            end
            imgui.PopItemWidth()
            
        elseif active_tab == 2 then
            imgui.TextColored(imgui.ImVec4(0.95, 0.30, 0.30, 1.00), u8"ВЫБОР И НАСТРОЙКА ФРАКЦИИ")
            imgui.Separator()
            imgui.Spacing()

            imgui.Text(u8"Выберите вашу организацию:")
            imgui.Spacing()
            
            local function DrawFractionSelector(label, frac_id)
                if ini_data.settings.fraction == frac_id then
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.85, 0.24, 0.24, 1.00))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.95, 0.30, 0.30, 1.00))
                    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.70, 0.18, 0.18, 1.00))
                else
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.14, 0.14, 0.17, 1.00))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.20, 0.25, 1.00))
                    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.11, 0.11, 0.14, 1.00))
                end
                if imgui.Button(u8(label), imgui.ImVec2(130, 30)) then
                    ini_data.settings.fraction = frac_id
                    inicfg.save(ini_data, direct_ini)
                end
                imgui.PopStyleColor(3)
            end

            DrawFractionSelector("Не выбрана", 0)
            imgui.SameLine()
            DrawFractionSelector("ФСБ", 1)
            imgui.SameLine()
            DrawFractionSelector("МВД (Полиция)", 2)

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            if ini_data.settings.fraction == 1 then
                imgui.TextColored(imgui.ImVec4(0.35, 0.65, 0.95, 1.00), u8"Настройки для сотрудника ФСБ:")
                imgui.PushItemWidth(280)
                if imgui.InputText(u8"Позывной", buf_fsb_callsign, 128) then
                    ini_data.settings.fsb_callsign = u8:decode(ffi.string(buf_fsb_callsign))
                    inicfg.save(ini_data, direct_ini)
                end
                if imgui.InputText(u8"Звание / Должность", buf_fsb_rank, 128) then
                    ini_data.settings.fsb_rank = u8:decode(ffi.string(buf_fsb_rank))
                    inicfg.save(ini_data, direct_ini)
                end
                imgui.PopItemWidth()
            elseif ini_data.settings.fraction == 2 then
                imgui.TextColored(imgui.ImVec4(0.30, 0.85, 0.40, 1.00), u8"Настройки для сотрудника МВД:")
                imgui.PushItemWidth(280)
                if imgui.InputText(u8"Позывной", buf_mvd_callsign, 128) then
                    ini_data.settings.mvd_callsign = u8:decode(ffi.string(buf_mvd_callsign))
                    inicfg.save(ini_data, direct_ini)
                end
                if imgui.InputText(u8"Звание / Должность", buf_mvd_rank, 128) then
                    ini_data.settings.mvd_rank = u8:decode(ffi.string(buf_mvd_rank))
                    inicfg.save(ini_data, direct_ini)
                end
                imgui.PopItemWidth()
            else
                imgui.TextColored(imgui.ImVec4(0.95, 0.30, 0.30, 1.00), u8"Пожалуйста, выберите фракцию кликом по кнопке выше.")
            end

        elseif active_tab == 3 then
            imgui.TextColored(imgui.ImVec4(0.30, 0.85, 0.40, 1.00), u8"СПРАВОЧНИК ПО КЛАВИШАМ")
            imgui.Separator()
            imgui.Spacing()
            
            imgui.TextColored(imgui.ImVec4(0.95, 0.70, 0.20, 1.00), u8"Комбинации (Alt + N):")
            imgui.Text(u8"• Alt + 1  Наручники + Вести за собой -> Приветствие")
            imgui.Text(u8"• Alt + 2  Высадить преступника из авто (/ceject)")
            imgui.Text(u8"• Alt + 3  Затолкнуть в автомобиль (/cput)")
            imgui.Text(u8"• Alt + 4  Надеть мешок на голову (/box)")
            
            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()
            
            imgui.TextColored(imgui.ImVec4(0.95, 0.70, 0.20, 1.00), u8"Консольные команды:")
            imgui.Text(u8"• /t [ID]   Зафиксировать / переключить ID игрока")
            imgui.Text(u8"• /mir [ID] Прочесть правила Миранды")
            imgui.Text(u8"• /smir     Экстренно остановить чтение Миранды")
            imgui.Text(u8"• /foff     Красивый выход из ООС-рации фракции")
            imgui.Text(u8"• /mhelp    Открыть/закрыть это меню конфигурации")
        end
        imgui.EndChild()
        imgui.End()
        
        if font_normal then imgui.PopFont() end 
        imgui.PopStyleVar()
    end
)

function main()
    while not isSampAvailable() do wait(0) end
   
    sampAddChatMessage("{853D3D}[MHelper]{FFFFFF} Скрипт запущен в режиме Stealth UI. Настройки: {853D3D}/mhelp", -1)

    checkUpdates(false)

    sampRegisterChatCommand('t', function(arg)
        if not checkFactionSelected() then return end
        
        local id = arg:match("(%d+)")
        if id then
            saved_id = tonumber(id)
            saved_name = sampGetPlayerNickname(saved_id) or "Неизвестный"
            sampAddChatMessage("{853D3D}[MHelper]{FFFFFF} Приоритет переключен на: {FFFF00}ID " .. saved_id .. " (" .. saved_name .. ")", -1)
        else
            saved_id = nil
            saved_name = "Unknown"
            sampAddChatMessage("{853D3D}[MHelper]{FFFFFF} Приоритетный ID сброшен. Автопоиск активен.", -1)
        end
    end)

    sampRegisterChatCommand('mir', function(arg)
        local id = arg:match("(%d+)") or saved_id
        if id then 
            readMiranda(id) 
        else
            if checkFactionSelected() then
                sampAddChatMessage("{FF6347}[MHelper]{FFFFFF} Нет цели для Миранды. Используйте /t [ID] or /mir [ID]", -1)
            end
        end
    end)

    sampRegisterChatCommand('smir', function()
        if not checkFactionSelected() then return end
        
        if miranda_thread and miranda_thread:status() ~= "dead" then
            miranda_thread:terminate()
            sampAddChatMessage("{853D3D}[MHelper]{FFFFFF} Миранда остановлена.", -1)
        else
            sampAddChatMessage("{FF6347}[MHelper]{FFFFFF} Поток чтения не активен.", -1)
        end
    end)

    sampRegisterChatCommand('mhelp', function()
        win_state[0] = not win_state[0]
    end)

    while true do
        wait(0)

        imgui.Process = (alpha > 0.0)
        imgui.ShowCursor = win_state[0]

        if isGameReady() then
            
            if isKeyDown(18) and wasKeyPressed(49) then
                if checkFactionSelected() and not is_processing then
                    local id = saved_id or getTargetPlayerId()
                    if id then
                        is_processing = true
                        
                        if not saved_id or saved_id ~= id then
                            saved_id = id
                            saved_name = sampGetPlayerNickname(id) or "Unknown_Player"
                            sampAddChatMessage("{853D3D}[MHelper]{FFFFFF} Цель задержания зафиксирована: {FFFF00}" .. saved_name .. " [" .. id .. "]", -1)
                        end
                        
                        lua_thread.create(function()
                            sampSendChat("/cuff " .. id)
                            wait(800)
                            sampSendChat("/follow " .. id)
                            wait(800)
                            
                            if ini_data.settings.fraction == 1 then
                                local callsign = ini_data.settings.fsb_callsign
                                if callsign == "" then callsign = "неизвестен" end
                                sampSendChat(string.format("Здравия желаю! Являюсь оперативником ФСБ, личный позывной: %s. Задержаны будете.", callsign))
                            elseif ini_data.settings.fraction == 2 then
                                local rank = ini_data.settings.mvd_rank
                                if rank == "" then rank = "сотрудником" end
                                sampSendChat(string.format("Здравия желаю! Являюсь %s Полиции. В данный момент вы будете задержаны.", rank))
                            end
                            
                            is_processing = false
                        end)
                    else
                        sampAddChatMessage("{FF6347}[MHelper]{FFFFFF} Цель не найдена.", -1)
                    end
                end
            end

            if isKeyDown(18) and wasKeyPressed(50) then
                if checkFactionSelected() and not is_processing then
                    local id = saved_id or getTargetPlayerId()
                    if id then 
                        is_processing = true
                        sampSendChat("/ceject " .. id) 
                        lua_thread.create(function()
                            wait(1000) 
                            is_processing = false
                        end)
                    end
                end
            end

            if isKeyDown(18) and wasKeyPressed(51) then
                if checkFactionSelected() and not is_processing then
                    local id = saved_id or getTargetPlayerId()
                    if id then 
                        is_processing = true
                        sampSendChat("/cput " .. id) 
                        lua_thread.create(function()
                            wait(1000)
                            is_processing = false
                        end)
                    end
                end
            end

            if isKeyDown(18) and wasKeyPressed(52) then
                if checkFactionSelected() and not is_processing then
                    local id = saved_id or getTargetPlayerId()
                    if id then 
                        is_processing = true
                        sampSendChat("/box " .. id) 
                        lua_thread.create(function()
                            wait(1000)
                            is_processing = false
                        end)
                    end
                end
            end
            
        end
    end
end