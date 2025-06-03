
--[[
飞书工具：https://open.feishu.cn/app/cli_axxx/baseinfo
飞书开放平台文档：https://open.feishu.cn/document/server-docs/docs/bitable-v1/app-table-record/create
上报的飞书表格：https://leiting.feishu.cn/wiki/NFSxxxh?table=tbxxx
]]


declare_module('BUG_REPORT_MGR')
local self = BUG_REPORT_MGR
self.ENABLE_DEBUG = false

local APP_ID = "cli_a88xxx"
local APP_SECRET = "QGxxxxxx"
local BITABLE_TOKEN = "Njfxxxxx" --飞书表格的token，也叫obj_token、app_token

-- 请求URL
local URL = {
    TENANT_ACCESS_TOKEN = "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal",
    GET_ALL_TABLES = "https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables",
    CREATE_TABLE =   "https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables",
    GET_TEMPLATE_TABLE_FIELDS = "https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables/%s/fields",
    UPLOAD_IMG_RECORD = "https://open.feishu.cn/open-apis/drive/v1/medias/upload_all",
    UPLOAD_BITABLE_RECORD = "https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables/%s/records/batch_create",
    SEARCH_TARGET_BITABLE_RECORD = "https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables/%s/records/search",
    SEARCH_BLACK_LIST_BITABLE_RECORD = "https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables/%s/records/search",
    
}

-- 表格ID
local BITABLE_ID = {
    DEFAULT_TABLE = "tblxxx", -- 默认表
    BLACK_LIST = "tblaxxx"     -- 黑名单
}

-- 上传状态
local UPLOAD_STATE = {
    NONE = 0,
    UPLOADING = 1,
    SUCCESS = 2,
    FAILED = 3,
    WAIT_IMG = 4,
    WAIT_IMG_DONE = 5,
    
    IMG_GRAB_SCREEN = 10,
    IMG_START_UPLOAD = 11,
    IMG_UPLOADING = 12,
    IMG_SUCCESS = 13,
    IMG_FAILED = 14,
}

-- 表格字段
local TABLE_FIELD = {
    INFO = "问题",
    IMG = "附件",
    --VERSION = "版本",
    RID = "RID",
    TAG = "Tag",
    LANGUAGE = "语言",
    BIG_TYPE = "类型",
    SUB_TYPE = "子类型",
    UPLOAD_INFO = "上报信息",
    
    TYPE_LOG_ERORR = "报错",
    TYPE_HAS_CHINESE = "中文",
}

-- 黑名单表配置类型
local BLACK_LIST_TYPE =
{
    FULL_LOG_CHECK = "full_log_check",
    PRE_LOG_CHECK = "pre_log_check",
    CHINESE_NODE = "chinese_node",
    CHINESE_PATH = "chinese_node_path",
    CHINESE_TEXT = "chinese_text",
    CHINESE_STACK_TRACE = "chinese_stack_trace",
}

-- 报错分类
local ERROR_LOG_SUB_TYPE = 
{
    ["加载国际化图片失败"] = "本地化缺图"
}


-- 刷新时间间隔重试
local REFRESH_CONST = 
{
    ACCESS_TOKEN_INTERVAL = 5,      -- 认证token刷新时间间隔
    SEARCH_CACHE_INTERVAL = 60,     -- 表格缓存时间间隔
    HTTP_REQ_TIMEOUT = 10,          -- Http请求超时时间
    IMG_UPLOAD_RETRY = 3,           -- 图片上传重试次数
    IMG_UPLOAD_RETRY_INTERVAL = 5,  -- 图片上传重试时间间隔
    TABLE_UPLOAD_RETRY = 3,         -- 表格数据上传重试次数
    TABLE_UPLOAD_RETRY_INTERVAL = 5,-- 表格数据上传重试时间间隔
}

function __create()
    EVENT_MGR.register_event_listen('EVT_RESET', self)
    EVENT_MGR.register_event_listen('EVT_USER_LOGIN_OK', self)
    
    if CONST.DEV and DEVICE_MGR.is_mobile_device() then
        set_enable(true)
    end
end

function __destroy()
    reset()
    EVENT_MGR.unregister_events_listen(self)
end

function on_evt_reset()
    reset()
end

function on_lua_quit()
    reset()
end

function on_evt_user_login_ok()
    self._game_user_rid = tostring(REMOTE_MGR.get_me_server_id()).."_"..tostring(ME_MGR.get_rid())
end

function get_game_user_rid()
    if is_string(self._game_user_rid) and self._game_user_rid ~= "" then
        return self._game_user_rid
    end
    if not REMOTE_MGR.get_me_server_id() or not ME_MGR.get_rid() then
        return nil
    end
    
    self._game_user_rid = tostring(REMOTE_MGR.get_me_server_id()).."_"..tostring(ME_MGR.get_rid())
    return self._game_user_rid
end
    
function set_enable(enable)
    self._enable = enable
    reset()
    if enable then
        init()
    end
end

function init()
    -- 旧包不支持截图
    if not System.Collections.Generic.List_UnityEngine_Networking_IMultipartFormSection then
        self._is_not_support_img = true
    end
    self._tenant_access_token = nil
    self._cur_bitable_id = nil
    self._is_black_list_init = false
    self._all_bitable_info = {}
    self._bitable_field_template = {}
    self._exist_bitable_cache = {}
    self._black_list_pre_log_bitable_cache = {}
    self._upload_table_records = {}
    self._failed_table_records = {}
    self._upload_img_records = {}
    self._failed_img_records = {}
    self._success_img_records = {}
    self._record_handle = 0
    self._last_refresh_tenant_access_token_time = 0
    self._last_refresh_all_bitable_info_time = 0
    self._last_refresh_bitable_cache_time = 0
    
    self._game_version = VERSION_MGR.get_cur_local_version()
    self._game_tag = get_game_tag()
    self._game_lang = I18N_MGR.get_cur_lang()

    URL.GET_ALL_TABLES = string.format(URL.GET_ALL_TABLES, BITABLE_TOKEN)
    URL.CREATE_TABLE = string.format(URL.CREATE_TABLE, BITABLE_TOKEN)
    URL.GET_TEMPLATE_TABLE_FIELDS = string.format(URL.GET_TEMPLATE_TABLE_FIELDS, BITABLE_TOKEN, BITABLE_ID.DEFAULT_TABLE)
    URL.SEARCH_BLACK_LIST_BITABLE_RECORD = string.format(URL.SEARCH_BLACK_LIST_BITABLE_RECORD, BITABLE_TOKEN, BITABLE_ID.BLACK_LIST)

    
    refresh_tenant_access_token(self.on_get_tenant_access_token)
    -- 测试异常token
    --self._tenant_access_token = "t-g1044hgIBHJAEKMYXZUYCLYHPONAZSOZYD5H7CM4"
    --self._url_auth_header = "Bearer " .. self._tenant_access_token
    
    -- 扫描中文
    init_text_modified_listener()
    init_scan_chinese_tool()
    
    -- 报错日志
    init_log_receive()
    
    -- 中文环境不检查
    if is_scan_chinese() then
        UPDATE.register_time_update(1, self.on_scan_text_has_chinese_update)
    end
    UPDATE.register_unscaledtime_update(0.2, self.on_update)
end

function reset()
    UPDATE.unregister_unscaledtime_update(self.on_update)
    UPDATE.unregister_time_update(self.on_scan_text_has_chinese_update)
    reset_text_modified_listener()
    reset_log_receive()
end

-- 中文环境不检查
function is_scan_chinese()
    return I18N_MGR.get_cur_lang() ~= "zh_cn"
end

function pop_record_handle()
    self._record_handle = self._record_handle + 1
    return self._record_handle
end

function init_log_receive()
    UnityEngine.Application.logMessageReceived = UnityEngine.Application.logMessageReceived + self.on_log_receive
end

function reset_log_receive()
    UnityEngine.Application.logMessageReceived = UnityEngine.Application.logMessageReceived - self.on_log_receive
end

function on_log_receive(logString, stackTrace, type)
    local type_str = tostring(type)
    if type_str ~= "Error" and type_str ~= "Exception" then
        return
    end
    if string.find(logString, 'bug_report_mgr') then
        return
    end
    record_error_log(logString, stackTrace)
end


-- 刷新认证token
function refresh_tenant_access_token(callback)
    local cur_time = os.time()
    -- 失败5秒后再重试
    if cur_time < self._last_refresh_tenant_access_token_time + REFRESH_CONST.ACCESS_TOKEN_INTERVAL then
        return
    end
    self._last_refresh_tenant_access_token_time = cur_time
    self._is_doing_refresh_tenant_access_token = true
    
    local head_data = { ["Content-Type"] = "application/json" }
    local body_data = { ["app_id"] = APP_ID, ["app_secret"] = APP_SECRET }
    http_post(URL.TENANT_ACCESS_TOKEN, head_data, body_data, nil, function (handle, req, is_success, result)
        self._is_doing_refresh_tenant_access_token = false
        if not is_success then
            return
        end
            
        if result.code ~= 0 or not is_string(result.tenant_access_token) then
            log_error("请求结果异常 refresh_tenant_access_token2:(url=%s)【%s】", req.url, pts(result))
            return
        end

        self._tenant_access_token = result.tenant_access_token
        self._url_auth_header = "Bearer " .. result.tenant_access_token
        log_debug("拿到tenant_access_token[%s]", self._url_auth_header)
        if callback then
            callback()
        end
    end)
end

function on_get_tenant_access_token()
    refresh_all_bitable_info(true)
end

-- 加载所有分表记录，找到当前版本号对应分表
function refresh_all_bitable_info(force)
    local cur_time = os.time()
    -- 定期拉取刷新
    if not force and cur_time < self._last_refresh_all_bitable_info_time + REFRESH_CONST.SEARCH_CACHE_INTERVAL then
        return
    end
    self._last_refresh_all_bitable_info_time = cur_time
    
    local head_data = { ["Content-Type"] = "application/json", ["Authorization"] = self._url_auth_header}
    http_get(URL.GET_ALL_TABLES, head_data, nil, function (handle, req, is_success, result)
        if not is_success then
            return
        end
        
        on_get_all_bitableinfo(result)
    end)
    
end

-- 刷新当前表格url，没有就创建
function on_get_all_bitableinfo(result)
    self._all_bitable_info = {}
    for _, item in pairs(result.data.items) do
        local table_name = item["name"]
        self._all_bitable_info[table_name] = item
    end
    
    local cur_table = self._all_bitable_info[self._game_version]
    if cur_table then
        refresh_cur_bitable_id(cur_table["table_id"])
        return
    end
    
    --找不到，创建一个
    --先取模板，在创建
    refresh_table_field_template(function ()
        create_cur_version_table()
    end)
end

-- 刷新当前目标的表格url
function refresh_cur_bitable_id(table_id)
    self._cur_bitable_id = table_id
    URL.UPLOAD_BITABLE_RECORD = string.format(URL.UPLOAD_BITABLE_RECORD, BITABLE_TOKEN, self._cur_bitable_id)
    URL.SEARCH_TARGET_BITABLE_RECORD = string.format(URL.SEARCH_TARGET_BITABLE_RECORD, BITABLE_TOKEN, self._cur_bitable_id)
    
    refresh_bitable_cache()
end

-- 获取通用模板
function refresh_table_field_template(callback)
    
    local head_data = { ["Content-Type"] = "application/json", ["Authorization"] = self._url_auth_header}
    http_get(URL.GET_TEMPLATE_TABLE_FIELDS, head_data, nil, function (handle, req, is_success, result)
        if not is_success then
            return
        end
        
        self._bitable_field_template = result.data.items
        for _, item in pairs(self._bitable_field_template) do
            item["field_id"] = nil
            local property = item["property"]
            if is_table(property) and is_table(property.options) then
                for _, options in pairs(property.options) do
                    options.id = nil --带这个字段复制表格失败
                end
            end
        end
        
        if callback then
            callback()
        end
    end)
end

--创建当前版本的表
function create_cur_version_table(callback)
    
    local head_data = { ["Content-Type"] = "application/json", ["Authorization"] = self._url_auth_header}
    local body_data = {
        ["table"] = {
            ["name"] = self._game_version,
            ["default_view_name"] = "表格",
            ["fields"] = self._bitable_field_template
        },
    }

    http_post(URL.CREATE_TABLE, head_data, body_data, nil, function (handle, req, is_success, result)
        if not is_success then
            return
        end

        refresh_cur_bitable_id(result.data["table_id"])
    end)
end

-- 加载缓存
function refresh_bitable_cache(force)
    local cur_time = os.time()
    -- 定期拉取刷新
    if not force and cur_time < self._last_refresh_bitable_cache_time + REFRESH_CONST.SEARCH_CACHE_INTERVAL then
        return
    end
    self._last_refresh_bitable_cache_time = cur_time
    
    -- 本地缓存清掉重新赋值，包含黑名单和当前版本表所有log
    --self._exist_bitable_cache = {}
    search_and_set_table_info(URL.SEARCH_TARGET_BITABLE_RECORD, function (str_key, info_fields)
        self._exist_bitable_cache[str_key] = true
    end)
    
    -- 只处理黑名单
    search_and_set_table_info(URL.SEARCH_BLACK_LIST_BITABLE_RECORD, function (str_key, info_fields)
        local type = info_fields[TABLE_FIELD.BIG_TYPE]
        if type == BLACK_LIST_TYPE.FULL_LOG_CHECK then
            self._exist_bitable_cache[str_key] = true
        elseif type == BLACK_LIST_TYPE.PRE_LOG_CHECK then
            self._black_list_pre_log_bitable_cache[str_key] = true
        elseif is_scan_chinese() then
            if type == BLACK_LIST_TYPE.CHINESE_NODE 
            or type == BLACK_LIST_TYPE.CHINESE_PATH
            or type == BLACK_LIST_TYPE.CHINESE_TEXT 
            or type == BLACK_LIST_TYPE.CHINESE_STACK_TRACE then
                if self._text_blacklist[type] == nil then
                    self._text_blacklist[type] = {}
                end
                self._text_blacklist[type][str_key] = true
            end
        end
        self._is_black_list_init = true
    end)
end

-- 查找并记录已存在表数据
function search_and_set_table_info(url, callback)
    local head_data = { ["Content-Type"] = "application/json", ["Authorization"] = self._url_auth_header}
    local body_data = { 
        ["field_names"] = {TABLE_FIELD.INFO, TABLE_FIELD.BIG_TYPE},
    }
    
    http_post(url, head_data, body_data, nil, function (handle, req, is_success, result)
        if not is_success then
            return
        end

        for _, item in pairs(result.data.items) do
            local info_fields = item["fields"]
            local key = info_fields[TABLE_FIELD.INFO]
            local str_key = nil
            if key and key[1] and key[1]["text"] then
                str_key = key[1]["text"]
            end
            if str_key and callback then
                callback(str_key, info_fields)
            end
        end
    end)
end

-- 获取格式化表格数据
function get_format_upload_table_data(detail)
    if detail[TABLE_FIELD.INFO] == nil then
        log_error("异常表格数据格式：缺少‘问题’字段【{%s}】", pts(detail))
        return nil
    end
    
    local data = {
        --[TABLE_FIELD.VERSION] = self._game_version,
        [TABLE_FIELD.TAG] = self._game_tag,
        [TABLE_FIELD.RID] = get_game_user_rid(),
        [TABLE_FIELD.LANGUAGE] = self._game_lang,
    }
    for k, v in pairs(detail) do
        data[k] = v
    end
    
    return data
end

-- 获取格式化图片上传数据
function get_format_upload_img()
    local data = {
        ["file_name"] = "bug_screenshot.png",
        ["parent_type"] = "bitable_image",
        ["parent_node"] = BITABLE_TOKEN,
        --["size"] = tostring(bytes.Length),
        --["file"] = bytes
    }
    return data
end

--记录截图
function record_cur_screenshot()
    if self._is_not_support_img then
        return nil
    end
    -- 同一秒只截图一张，避免重复
    local cur_time = os.time()
    if self._last_screenshot_time == cur_time and self._last_screenshot_img_handle then
        return self._last_screenshot_img_handle
    end
    self._last_screenshot_time = cur_time 
    local img_handle = pop_record_handle()
    get_grab_screen_texture(img_handle, self.on_get_grab_screen_texture)
    local img_data = get_format_upload_img()
    
    local record = {
        handle = img_handle,
        retry_count = REFRESH_CONST.IMG_UPLOAD_RETRY, -- 重试3次
        last_upload_time = 0,
        upload_result = {}, -- 多次上传多次记录
        upload_state = UPLOAD_STATE.IMG_GRAB_SCREEN,
        img_handle = img_handle,
        img_data = img_data,
        file_token = nil, -- 上传成功返回的token
    }
    self._upload_img_records[img_handle] = record
    self._last_screenshot_img_handle = img_handle
    return img_handle
end

-- 拿到截图记录
function on_get_grab_screen_texture(img_handle, bytes)
    local record = self._upload_img_records[img_handle]
    if not record then
        return
    end
    if not bytes or bytes.Length < 0 then
        record.upload_state = UPLOAD_STATE.IMG_FAILED
        table.insert(record.upload_result, "grab_screen_texture_failed")
        return
    end
    record.upload_state = UPLOAD_STATE.IMG_START_UPLOAD
    record.img_data["size"] = tostring(bytes.Length)
    record.img_data["file"] = bytes
end

local ERROR_LOG_PERFIX = "[Error]"
local ERROR_LOG_TIME_PERFIX = "[Error] 12:59:59 "
-- 记录上报的报错
function record_error_log(log_string, stack_trace)
    
    local upload_str = log_string
    local sub_type = ""
    -- lua报错有前缀'[Error]'，去掉时间前缀，且不需要C#的堆栈
    if has_prefix(log_string, ERROR_LOG_PERFIX) then
        upload_str = string.sub(log_string, #ERROR_LOG_TIME_PERFIX + 1)
        sub_type = get_error_log_sub_type(upload_str)
    else
        upload_str = log_string .. "\n" .. stack_trace
    end
    
    add_record(upload_str, TABLE_FIELD.TYPE_LOG_ERORR, sub_type)
end

-- 添加一个上报记录
function add_record(upload_str, big_type, sub_type)
    -- 避免初始化黑名单前有在黑名单的报错，所以就先不记录
    if not self._is_black_list_init then
        return
    end
    
    -- 查重
    if self._exist_bitable_cache[upload_str] then
        log_debug("重复报错不上报：【%s】", upload_str)
        return
    end
    -- 本地记录缓存，原来成功才上传，现在记录就马上缓存，避免短时间内大量重复报错
    self._exist_bitable_cache[upload_str] = true
    
    for prefix, _ in pairs(self._black_list_pre_log_bitable_cache) do
        if has_prefix(upload_str, prefix) then
            log_debug("黑名单报错前缀不上报：【%s】【%s】", prefix, upload_str)
            return
        end
    end
    
    --截图上报
    local img_handle = record_cur_screenshot()
    
    local upload_data = {
        [TABLE_FIELD.INFO] = upload_str,
        [TABLE_FIELD.BIG_TYPE] = big_type,
        [TABLE_FIELD.SUB_TYPE] = sub_type
    }
    upload_data = get_format_upload_table_data(upload_data)
    
    local state = UPLOAD_STATE.NONE
    if img_handle then
        state = UPLOAD_STATE.WAIT_IMG
    end
    
    local handle = pop_record_handle()
    local record = {
        handle = handle,
        retry_count = REFRESH_CONST.TABLE_UPLOAD_RETRY, -- 重试3次
        last_upload_time = 0, -- 最后上传的时间
        upload_data = upload_data,
        upload_result = {}, -- 多次上传多次记录
        upload_state = state,
        img_handle = img_handle,
        extra_info = {}, --其他信息
    }
    
    self._upload_table_records[handle] = record
    return record
end

-- 报错子类型
function get_error_log_sub_type(str)
    for key, sub_type in pairs(ERROR_LOG_SUB_TYPE) do
        if has_prefix(str, key)then
            return sub_type
        end
    end
    return ""
end

function on_update()
    if self._is_doing_refresh_tenant_access_token then
       return 
    end

    if self._tenant_access_token == nil or self._cur_bitable_id == nil then
        refresh_tenant_access_token(self.on_get_tenant_access_token)
        return
    end
    
    local cur_time = os.time()
    -- 处理图片
    on_upload_img_update(cur_time)
    -- 处理表格
    on_upload_table_update(cur_time)
    
    -- 刷新缓存
    refresh_bitable_cache()
end

-- 监听文本修改，记录修改堆栈
function init_text_modified_listener()
    local cur_lang = I18N_MGR.get_cur_lang()
    if cur_lang == 'zh_cn' then
        return false
    end
    local success = I18N_POSTPROCESS_TEXT_MGR.init_stack_trace(true, 3)
    if not success then
        return false
    end
    I18N_POSTPROCESS_TEXT_MGR.set_text_modified_listener(on_text_modified)
    return true
end

function reset_text_modified_listener()
    I18N_POSTPROCESS_TEXT_MGR.set_text_modified_listener(nil)
end

function on_text_modified(ob, text, stack_trace)
    if not is_contains_chinese(text) or not self._text_com_info then
        return
    end

    if self._text_com_info[ob] == nil then
        self._text_com_info[ob] = {}
    end
    self._text_com_info[ob].text = text
    self._text_com_info[ob].stack_trace = stack_trace
end

local TEXT_COM_TYPE = 
{
    TEXT = _typeof(UnityEngine.UI.Text),
    TMP_TEXT = _typeof(TMPro.TMP_Text),
}

-- 初始化
function init_scan_chinese_tool()
    self._chinese_cache = {}
    self._text_com_info = {}
    self._text_blacklist = {}
end

-- 扫描所有
function on_scan_text_has_chinese_update()
    if not self._is_black_list_init then
        return
    end
    
    if self._game_canvas == nil then
        self._game_canvas = Client.Game.MainCanvas.transform
    end
    if self._game_canvas == nil then
        return
    end
    
    local result_list = {}
    collect_all_chinese_text(self._game_canvas, TEXT_COM_TYPE.TEXT, result_list)
    collect_all_chinese_text(self._game_canvas, TEXT_COM_TYPE.TMP_TEXT, result_list)
    if next(result_list) == nil then
        return 
    end
    local text_list = {}
    local upload_str = ""
    for com, info in pairs(result_list) do
        table.insert(text_list, string.format("text:【%s】path:【%s】", info.text, info.path))
    end
    upload_str = "【有中文】\n" .. table.concat(text_list, '\n')
    add_record(upload_str, TABLE_FIELD.TYPE_HAS_CHINESE, nil)
end

-- 收集中文和对应组件路径
function collect_all_chinese_text(root, type, result_list)
    local childs = root:GetComponentsInChildren(type)
    for i = 0, childs.Length - 1 do
        local com = childs[i]
        local info = self._text_com_info[com]
        local cur_text = com.text
        if self._text_blacklist[BLACK_LIST_TYPE.CHINESE_TEXT][cur_text] then
            --local a = 0
            -- 文本在黑名单
        elseif info and (info.in_black_list or info.upload_text == cur_text) then
            -- 节点在黑名单的跳过，或之前记录过跳过
        elseif com:IsActive() and is_contains_chinese(cur_text) then
            local in_black_list = false
            local path = ""
            -- 如果有记录，不重新计算节点
            if info and info.path then
                path = info.path
                in_black_list = info.in_black_list
            else
                in_black_list, path = get_node_path(root, com.transform)
            end
            if info == nil then
                self._text_com_info[com] = {}
                info = self._text_com_info[com]
            end
            info.in_black_list = info.in_black_list
            info.path = info.path
            info.text = cur_text -- 刷新缓存记录文本
            info.upload_text = cur_text
            -- 不在节点黑名单
            -- 那就看看在不在堆栈黑名单
            if not in_black_list and info.stack_trace then
                local trace = info.stack_trace
                in_black_list = self.is_stack_trace_in_black_list(trace)
            end

            if not in_black_list then
                result_list[com] = {text = cur_text , path = path}
            end
        end
    end
end

-- 获取节点路径，抄I18N_PROPERTY_MGR
-- 返回第一个参数为是否在黑名单
function get_node_path(root, node)
    if not root or not node then
        return false, nil
    end
    if root == node then
        return false, ''
    end

    local ret = {}
    local cur = node
    while cur and cur ~= root do
        local name = cur.name
        if self._text_blacklist[BLACK_LIST_TYPE.CHINESE_NODE][name] then
            return true, node.name
        end
        table.insert(ret, 1, name)
        cur = cur.parent
    end
    local result = table.concat(ret, '/')

    if self._text_blacklist[BLACK_LIST_TYPE.CHINESE_PATH][result] then
        return true, result
    end
    return false, result
end

function is_contains_chinese(str)
    local cache = self._chinese_cache[str]
    if cache ~= nil then
        return cache
    end
    local is_contains = UTIL.contains_chinese_char(str)
    self._chinese_cache[str] = is_contains
    return is_contains
end

function is_stack_trace_in_black_list(str)
    local map = self._text_blacklist[BLACK_LIST_TYPE.CHINESE_STACK_TRACE]
    for key, _ in pairs(map) do
        if string.find(str, key) then
            return true
        end
    end
    return false
end

-- 上传图片
function on_upload_img_update(cur_time)
    if next(self._upload_img_records) == nil then
        return
    end
    
    local wait_to_upload_records = {}
    local finished_records = {}
    for handle, record in pairs(self._upload_img_records) do
        -- 还在截屏，等一会
        if record.upload_state == UPLOAD_STATE.IMG_GRAB_SCREEN then
            --DO NOTHING
            
        -- 记录开始上传
        elseif record.upload_state == UPLOAD_STATE.IMG_START_UPLOAD then
            table.insert(wait_to_upload_records, handle)
            
        -- 记录成功的
        elseif record.upload_state == UPLOAD_STATE.IMG_SUCCESS then
            self._success_img_records[handle] = record
            table.insert(finished_records, handle)
            
        -- 失败重试
        elseif record.upload_state == UPLOAD_STATE.IMG_FAILED then
            if record.retry_count <= 1 then
                self._failed_img_records[handle] = record
                table.insert(finished_records, handle)
            else
                if cur_time > record.last_upload_time + REFRESH_CONST.IMG_UPLOAD_RETRY_INTERVAL then
                    record.retry_count = record.retry_count - 1
                    table.insert(wait_to_upload_records, handle)
                end
            end
        end
    end

    -- 清理已经完成的（包括成功失败）
    for _, handle in ipairs(finished_records) do
        self._upload_img_records[handle] = nil
    end

    -- 上报
    upload_img_records(wait_to_upload_records)
end

-- 批量上报记录
function upload_img_records(handle_arr)
    if #handle_arr <= 0 then
        return
    end
    
    for _, handle in ipairs(handle_arr) do
        upload_one_img_record(handle)
    end
end

-- 上传一个图片资源
function upload_one_img_record(handle)
    log_debug("upload_one_img_record [%s]",handle)
    local record = self._upload_img_records[handle]
    record.upload_state = UPLOAD_STATE.IMG_UPLOADING
    record.last_upload_time = os.time()
    
    local head_data = { 
        --["Content-Type"] = "multipart/form-data; boundary=---7MA4YWxkTrZu0gW", 
        ["Authorization"] = self._url_auth_header
    }
    local body_data = record.img_data
    
    -- 上传
    http_post_multipart(URL.UPLOAD_IMG_RECORD, head_data, body_data, handle, function (handle, req, is_success, result)
        if not is_success then
            on_img_upload_fail(handle, req, result)
            return
        end
            
        on_img_upload_success(handle, result)
    end)
end

-- 上传失败
function on_img_upload_fail(handle, req, result)
    local record = self._upload_img_records[handle]
    if not is_table(result) then
        result = req.error
    end
    record.upload_state = UPLOAD_STATE.IMG_FAILED
    table.insert(record.upload_result, pts(result))
end

-- 上传成功
function on_img_upload_success(handle, result)
    local record = self._upload_img_records[handle]
    record.file_token = result.data.file_token
    record.upload_state = UPLOAD_STATE.IMG_SUCCESS
end

-- 获取图片状态，
-- 返回值：参数1：状态；参数2：成功是token，失败是原因
function get_img_state_and_file_token(img_handle)
    if self._upload_img_records[img_handle] then
        return UPLOAD_STATE.IMG_UPLOADING
    end
    local failed_record = self._failed_img_records[img_handle]
    if failed_record then
        local reason = failed_record.upload_result[#failed_record.upload_result]
        return UPLOAD_STATE.IMG_FAILED, reason
    end
    local success_record = self._success_img_records[img_handle]
	if success_record then
        return UPLOAD_STATE.IMG_SUCCESS, success_record.file_token
    end
    
    -- 异常，没用handle记录
    return UPLOAD_STATE.IMG_FAILED, string.format("img_handle_not_exist[%s]", img_handle)
end

-- 上传数据
function on_upload_table_update(cur_time)
    if next(self._upload_table_records) == nil then
        return
    end
    
    local wait_to_upload_records = {}
    local finished_records = {}
    for handle, record in pairs(self._upload_table_records) do
        -- 先检查图片上传情况
        if record.upload_state == UPLOAD_STATE.WAIT_IMG then
            local img_state, result = get_img_state_and_file_token(record.img_handle)
            if img_state == UPLOAD_STATE.IMG_SUCCESS then
                record.upload_data[TABLE_FIELD.IMG] = {{["file_token"] = result}}
            elseif img_state == UPLOAD_STATE.IMG_FAILED then
                record.extra_info["img_error"] = result
            end
            -- 图片上传结束，可能成功或失败
            if img_state ~= UPLOAD_STATE.IMG_UPLOADING then
                record.upload_state = UPLOAD_STATE.WAIT_IMG_DONE
            end
        end
        
        -- 记录开始上传
        if record.upload_state == UPLOAD_STATE.NONE or 
            record.upload_state == UPLOAD_STATE.WAIT_IMG_DONE then
            table.insert(wait_to_upload_records, handle)
            
        -- 记录成功的
        elseif record.upload_state == UPLOAD_STATE.SUCCESS then
            table.insert(finished_records, handle)
            
        -- 失败重试
        elseif record.upload_state == UPLOAD_STATE.FAILED then
            if record.retry_count <= 1 then
                self._failed_table_records[handle] = record
                table.insert(finished_records, handle)
            else
                if cur_time > record.last_upload_time + REFRESH_CONST.TABLE_UPLOAD_RETRY_INTERVAL then
                    record.retry_count = record.retry_count - 1
                    table.insert(wait_to_upload_records, handle)
                end
            end
        end
    end
    
    -- 清理已经完成的
    for _, handle in ipairs(finished_records) do
        self._upload_table_records[handle] = nil
    end 
    
    -- 上报
    upload_table_records(wait_to_upload_records)
end

-- 批量上报记录
function upload_table_records(handle_arr)
    if #handle_arr <= 0 then
        return
    end
    
    local head_data = { ["Content-Type"] = "application/json" , ["Authorization"] = self._url_auth_header}
    local body_data = { ["records"] = {}}
    
    -- 更新状态
    for _, handle in ipairs(handle_arr) do
        local record = self._upload_table_records[handle]
        --dump("foreach_records")
        record.upload_state = UPLOAD_STATE.UPLOADING
        record.last_upload_time = os.time()
        record.upload_data[TABLE_FIELD.UPLOAD_INFO] = pts(record.extra_info)
        local str_json_data = json.encode(record.upload_data)
        table.insert(body_data["records"], {["fields"] = record.upload_data})
    end
    
    -- 上传
    http_post(URL.UPLOAD_BITABLE_RECORD, head_data, body_data, handle_arr, function (handle_arr, req, is_success, result)
        if not is_success then
            on_table_upload_fail(handle_arr, req, result)
            return
        end
        on_table_upload_success(handle_arr, result)
    end)
end

-- 上传失败
function on_table_upload_fail(handle_arr, req, result)
    if not is_table(result) then
        result = req.error
    end
    
    for _, handle in ipairs(handle_arr) do
        local record = self._upload_table_records[handle]
        record.upload_state = UPLOAD_STATE.FAILED
        table.insert(record.upload_result, pts(result))
    end
end

-- 上传成功
function on_table_upload_success(handle_arr, result)
    for _, handle in ipairs(handle_arr) do
        local record = self._upload_table_records[handle]
        record.upload_state = UPLOAD_STATE.SUCCESS
    end
end

-- 处理常见报错
function handle_common_http_error(result)
    if not is_table(result) then
        return
    end
    if result.code == 99991663 or result.code == 99991661 then
        refresh_tenant_access_token() -- 重刷token
    end
end

function http_get(url, head_data, handle, callback)
    log_debug("http_get【%s】【%s】", url, pts(head_data))
    local req = UnityEngine.Networking.UnityWebRequest.Get(url)
    req.timeout = REFRESH_CONST.HTTP_REQ_TIMEOUT
    for key, value in pairs(head_data) do
        req:SetRequestHeader(key, value)
    end

    http_send(req, handle, callback)
end

function http_post(url, head_data, body_data, handle, callback)
    log_debug("http_post【%s】【%s】【%s】", url, pts(head_data), pts(body_data))
    local req = UnityEngine.Networking.UnityWebRequest(url, "POST")
    local body_raw = json.encode(body_data)
    req.timeout = REFRESH_CONST.HTTP_REQ_TIMEOUT
    req.uploadHandler = UnityEngine.Networking.UploadHandlerRaw(body_raw)
    req.downloadHandler = UnityEngine.Networking.DownloadHandlerBuffer()
    for key, value in pairs(head_data) do
        req:SetRequestHeader(key, value)
    end
    
    http_send(req, handle, callback)
end

function http_post_multipart(url, head_data, body_data, handle, callback)
    log_debug("http_post_multipart【%s】【%s】【%s】", url, pts(head_data), pts(body_data))
    -- 构建表单数据
    local form_list_type = System.Collections.Generic.List_UnityEngine_Networking_IMultipartFormSection
    local form_list = form_list_type()
    for key, value in pairs(body_data) do
        --logger:warn("http_post_multipart [%s][%s]",key, value)
        local form = UnityEngine.Networking.MultipartFormDataSection.New(key, value)
        form_list:Add(form)
    end
    local req = UnityEngine.Networking.UnityWebRequest.Post(url, form_list)
    req.timeout = REFRESH_CONST.HTTP_REQ_TIMEOUT
    req.downloadHandler = UnityEngine.Networking.DownloadHandlerBuffer()
    for key, value in pairs(head_data) do
        req:SetRequestHeader(key, value)
    end
    
    http_send(req, handle, callback)
end

function http_send(req, handle, callback)
    local op = req:SendWebRequest()
    StartCoroutine(function()
        Yield(op)
        log_debug("http_send done【%s】", req.url)
        local result = nil
        if not req.isDone or req.isNetworkError then
            log_error('请求失败 (url=%s)%s/%s/%s/%s', req.url, req.isDone, req.isNetworkError, req.isHttpError, req.error)
            if callback then callback(handle, req, false, result) end
            return
        end
        local text = req.downloadHandler.text
        if text == nil then
            log_error('请求返回空 (url=%s)%s/%s/%s/%s', req.url, req.isDone, req.isNetworkError, req.isHttpError, req.error)            
            if callback then callback(handle, req, false, result) end
            return
        end

        local res, err = pcall(function () result = json.decode(text) end)
        if not res or not result then
            result = text
            log_error("请求结果异常 (url=%s)【%s】", req.url, text)
            if callback then callback(handle, req, false, result) end
            return
        end
        if result.code ~= 0 then
            handle_common_http_error(result)
            log_error("请求结果异常 (url=%s)【%s】", req.url, pts(result))
            if callback then callback(handle, req, false, result) end
            return
        end
            
        -- 失败的result是nil或string，成功是table
        if callback then callback(handle, req, true, result) end
    end)
end

-- 暂不考虑分辨率变化
function get_texture_and_rect()
    if self._cache_texture and self._cache_rect then
        return self._cache_texture, self._cache_rect
    end 
    local width = UnityEngine.Screen.width
    local height = UnityEngine.Screen.height
    local tex = UnityEngine.Texture2D.New(width, height)
    local rect = UnityEngine.Rect.New(0, 0, width, height)
    self._cache_texture = tex
    self._cache_rect = rect
    return self._cache_texture, self._cache_rect
end

-- 截屏
function get_grab_screen_texture(handle, callback)
    StartCoroutine(function()
        WaitForEndOfFrame()
            
        local tex, rect = get_texture_and_rect()
        tex:ReadPixels(rect, 0, 0)
        tex:Apply()
        
        -- 编码为 PNG
        local bytes = UnityEngine.ImageConversion.EncodeToPNG(tex)
    
        pcall(function()
            if self.ENABLE_DEBUG then
                -- 保存文件
                local filePath = "bug_screenshot_temp.png"
                System.IO.File.WriteAllBytes(filePath, bytes)
            end
        end)
            
        callback(handle, bytes)
    end)
end

-- 获取打包的tag
function get_game_tag()
    local result = ""
    local res, err = pcall(function () 
        local str = StreamingAssetsHelper.ReadAllText("tag.txt")
        if is_string(str) and str ~= '' then
            result = str
        end
    end)
    return result
end

-- 字符串是否包含指定前缀
function has_prefix(str, prefix)
    return string.sub(str, 1, #prefix) == prefix
end

function log_error(str, ...)
    logger:error("[bug_report_mgr] " .. str, ...)
end

function log_debug(str, ...)
    if not self.ENABLE_DEBUG then
        return
    end
    logger:warn("[bug_report_mgr] " .. str, ...)
end

function dump(title)
    log_debug("dump start [%s]", title or "")
    log_debug("self._upload_table_records:【%s】", pts(self._upload_table_records))
    log_debug("self._failed_table_records:【%s】", pts(self._failed_table_records))
    log_debug("self._upload_img_records:【%s】", pts(self._upload_img_records))
    log_debug("self._failed_img_records:【%s】", pts(self._failed_img_records))
    log_debug("self._success_img_records:【%s】", pts(self._success_img_records))
    log_debug("dump end [%s]", title or "")
end

__create()
_G.BUG_REPORT_MGR = BUG_REPORT_MGR
