-- calculate entropy of an object
function object_entropy(full_name)

  local byte_hist = {}
  local byte_hist_size = 256 
  for i = 1,byte_hist_size do
    byte_hist[i] = 0 
  end 
  local total = 0 

  for i, c in pairs(Data)  do
    local byte = c:byte() + 1 
    byte_hist[byte] = byte_hist[byte] + 1 
    total = total + 1 
  end 

  entropy = 0 

  for _, count in ipairs(byte_hist) do
    if count ~= 0 then
      local p = 1.0 * count / total
      entropy = entropy - (p * math.log(p)/math.log(byte_hist_size))
    end 
  end 

  return entropy
end

function detect_ransomware()
  local suffix = "-quarantine"
  local bucket_name = Request.Bucket.Name

  if bucket_name:sub(-#suffix) == suffix then
    -- this is the quarantine bucket, no need to check
    RGWDebugLog("skipping entropy calculation for quarantine bucket "..bucket_name)
    return
  end

  if Request.RGWOp ~= 'put_obj' then
    -- calculate entropy only when uploading an object
    RGWDebugLog("skipping entropy calculation for "..Request.RGWOp)
    return
  end

  local full_name = bucket_name.."\\"..Request.Object.Name

  local upload_id = Request.HTTP.Parameters["uploadId"]

  if upload_id ~= nil then
    if RGW[full_name.."-upload-id"] == upload_id then
      -- calculate entropy only on the first part of a large object
      return
    end
    RGW[full_name.."-upload-id"] = upload_id
  end


  local new_entropy = object_entropy(full_name)
  if new_entropy == 0 then
    RGWDebugLog("no data in "..full_name)
    return
  end

  local current_entropy = RGW[full_name.."-entropy"]
  RGWDebugLog("current entropy of "..full_name.." is "..tostring(current_entropy))

  if current_entropy ~= nil then
    -- object with entropy already exists
    RGWDebugLog("object "..Request.Object.Name.." updated. entropy changed from "..tostring(current_entropy).." to "..tostring(new_entropy))
    
    local inc_threshold = 0.005 -- 0.5% increase in object entropy
    local enc_threshold = 0.9 -- minimum entropy for encryption
    local bucket_threshold = 0.2 -- if bucket has 20% encrypted files it is quarantines

    local inc_rate = (new_entropy - current_entropy)/current_entropy
    if inc_rate > inc_threshold and new_entropy > enc_threshold then
      RGWDebugLog("entropy of "..full_name.." increased by "..tostring(inc_rate*100).."%")
      if RGW[bucket_name.."-enc-count"] == nil then
        RGW[bucket_name.."-enc-count"] = 1
      else
        RGW.increment(bucket_name.."-enc-count")
      end
      enc_rate = RGW[bucket_name.."-enc-count"]/RGW[bucket_name.."-count"]
      RGWDebugLog(tostring(enc_rate*100).."% of the objects in "..bucket_name.." may be encrypted")
      if enc_rate > bucket_threshold then
        RGW[bucket_name.."-quarantine"] = true
      end
    end
  else
    RGWDebugLog("new object "..full_name.." uploaded. entropy is "..tostring(new_entropy))
    if RGW[bucket_name.."-count"] == nil then
      RGW[bucket_name.."-count"] = 1
    else
      RGW.increment(bucket_name.."-count")
    end
  end

  RGW[full_name.."-entropy"] = new_entropy
end

detect_ransomware()

