
if Request.RGWOp == 'put_obj' then
  if RGW[Request.Bucket.Name.."-quarantine"] == true then
    local new_bucket = Request.Bucket.Name.."-quarantine"
    RGWDebugLog("bucket "..Request.Bucket.Name.." is in quaratine state. changing bucket to "..new_bucket)
    Request.Bucket.Name = new_bucket
  else
    RGWDebugLog("bucket "..Request.Bucket.Name.." is not in quaratine state")                                                                                                                                                                 
  end 
end

