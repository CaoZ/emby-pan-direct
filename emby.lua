local http = require('resty.http')
local cjson = require('cjson')

local _M = {}

local HOST = "127.0.0.1"
local ALIST_HOST = string.format('http://%s:5244', HOST)
local ALIST_TOKEN = 'alist-a7a4844a-68c9-4241-acca-7df59df2b6b8xyzR5VpjflYoZuYjNXuH3lpmrjuvShIefnTcEehRVJrrTKy9xNa0mcTJtT5en2RM'

local EMBY_HOST = string.format('http://%s:8097', HOST)
local EMBY_TOKEN = 'ff69f6577eba4b5e9f0a7ebc9acb521d'
local EMBY_USER_ID = '7bf710d1e598402a95faabd782943730'
local EMBY_MOUNT_PATH = 'X:'

function _M.redirect_to_pan(item_id)
    local file_path = _M.get_file_path(item_id)

    if file_path and string.find(file_path, '^' .. EMBY_MOUNT_PATH) then
        -- 云盘文件
        ngx.log(ngx.ERR, '# real_path: ', file_path)
        
        local pan_path = _M.get_pan_path(file_path)

        if pan_path then
            ngx.redirect(pan_path)
        end
    end

    return file_path

end

-- 查询文件（硬盘）路径
function _M.get_file_path(item_id)
    local info_api = string.format('%s/Items/%s/PlaybackInfo?UserId=%s&api_key=%s', EMBY_HOST, item_id, EMBY_USER_ID, EMBY_TOKEN)
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
    -- ngx.log(ngx.ERR, '# real_path: ', file_path)

    return file_path
end

-- 查询文件网盘直链路径
function _M.get_pan_path(file_path)
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

    local pan_path = data.data.raw_url
    -- ngx.log(ngx.ERR, '# pan_path: ', pan_path)

    return pan_path

end

return _M