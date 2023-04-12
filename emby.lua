local http = require('resty.http')
local cjson = require('cjson')

local _M = {}

local HOST = "127.0.0.1"
local ALIST_HOST = string.format('http://%s:5244', HOST)
local ALIST_TOKEN = 'alist-a7a4844a-68c9-4241-acca-7df59df2b6b8xyzR5VpjflYoZuYjNXuH3lpmrjuvShIefnTcEehRVJrrTKy9xNa0mcTJtT5en2RM'

local EMBY_HOST = string.format('http://%s:8097', HOST)
local EMBY_TOKEN = '98449ad8d4ec46d98d774cd74425d224'
local EMBY_MOUNT_PATH = 'X:'
local CACHE_TIME = 3600 * 3  -- 从 x-oss-expires 得知返回 url 有效时间最大为 4 小时

function _M.redirect_to_pan(item_id)
    local file_path = _M.get_file_path(item_id)

    if file_path and string.find(file_path, '^' .. EMBY_MOUNT_PATH) then
        -- 云盘文件
        ngx.log(ngx.INFO, '# real_path: ', file_path)
        
        local pan_path = _M.get_pan_path(file_path)

        if pan_path then
            ngx.redirect(pan_path)
        end
    end

    return file_path

end

-- 查询文件（硬盘）路径
function _M.get_file_path(item_id)
    local info_api = string.format('%s/Items/%s/PlaybackInfo?api_key=%s', EMBY_HOST, item_id, EMBY_TOKEN)
    local httpc = http.new()

    local res, err = httpc:request_uri(info_api, {
        method = 'POST',
        headers = {
            ['Content-Type'] = 'application/json; charset=utf-8'
        }
    })

    if not res or res.status ~= 200 then
        ngx.log(ngx.ERR, '# get_file_path: request failed: ', err)
        ngx.log(ngx.ERR, '# get_file_path: status_code: ', res.status_code)
        return
    end

    local data = cjson.decode(res.body)
    local file_path = data.MediaSources[1].Path
    -- ngx.log(ngx.INFO, '# real_path: ', file_path)

    return file_path
end

-- 查询文件网盘直链路径
function _M.get_pan_path(file_path)
    local cache = ngx.shared.pan_paths
    local pan_path, _ = cache:get(file_path)

    if pan_path then
        return pan_path
    end

    local httpc = http.new()

    local res, err = httpc:request_uri(ALIST_HOST .. '/api/fs/get', {
        method = 'POST',
        headers = {
            ['Content-Type'] = 'application/json; charset=utf-8',
            ['Authorization'] = ALIST_TOKEN
        },
        body = cjson.encode({ path = string.sub(file_path, #EMBY_MOUNT_PATH + 1) })
    })

    if not res or res.status ~= 200 then
        ngx.log(ngx.ERR, '# get_pan_path: request failed: ', err)
        ngx.log(ngx.ERR, '# get_pan_path: status_code: ', res.status_code)
        return
    end

    local data = cjson.decode(res.body)

    if data.message ~= 'success' then
        ngx.log(ngx.ERR, '# get_pan_path: api error: ', data.message)
        return
    end

    pan_path = string.gsub(data.data.raw_url, 'https://', 'http://', 1)
    -- ngx.log(ngx.INFO, '# pan_path: ', pan_path)

    cache:set(file_path, pan_path, CACHE_TIME)

    return pan_path

end

return _M