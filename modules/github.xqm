xquery version "3.1";

(:~
 : Module providing functions to communicate with GitHub repository.
 :)
module namespace gh = "http://dracor.org/ns/exist/v1/github";

import module namespace config = "http://dracor.org/ns/exist/v1/config"
  at "config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/v1/util"
  at "util.xqm";

(:~
 : Analyze repository URL
 :
 : If the URL is recognized as Github URL a map providing account name, repo
 : name and branch name is returned. The branch name is extracted from a
 : fragment if available, otherwise it defaults to "main".
 :
 : @param $url Repository URL
 : @return map
 :)
declare function gh:parse-repo-url($url as xs:string) as map()? {
  let $regex := "^https://github\.com/([-_a-zA-Z0-9]+)/([-_a-zA-Z0-9]+)(?:\.git)?(?:#([-_a-zA-Z0-9]+))?$"
  let $match := analyze-string($url, $regex)
  let $account := $match//fn:group[@nr=1]/string()
  let $repo := $match//fn:group[@nr=2]/string()
  let $branch := $match//fn:group[@nr=3]/string()

  return if($match//fn:match) then map {
    "host": "https://github.com",
    "account": $account,
    "reponame": $repo,
    "branch": if($branch) then $branch else "main"
  } else ()
};


declare function local:get-head-sha($repo as map()) as xs:string* {
  let $ref-url := "https://api.github.com/repos/" || $repo?account || "/" ||
    $repo?reponame || "/git/refs/heads/" || $repo?branch
  let $response := hc:send-request(
    <hc:request method="get" href="{$ref-url}"/>
  )
  let $status := string($response[1]/@status)
  let $json := if($status = "200") then
    $response[2] => util:base64-decode() => parse-json()
  else (
    util:log-system-out("Failed to fetch " || $ref-url || " Status: " || $status),
    map{}
  )
  return $json?object?sha
};


(:~
 : Get commit hash of HEAD of a repository
 :
 : @param $url Repository URL
 : @return Commit hash
 :)
declare function gh:get-head-sha($url as xs:string) as xs:string* {
  let $repo := gh:parse-repo-url($url)
  return if(count($repo)) then
    local:get-head-sha($repo)
  else (
    util:log-system-out("Not a github repo? " || $url)
  )
};

(:~
 : Get URL to the ZIP archive for the HEAD of a repo and its commit hash
 :
 : @param $url Repository URL
 : @return Map
 :)
declare function gh:get-archive($url as xs:string) as map()* {
  let $repo := gh:parse-repo-url($url)
  return if(count($repo)) then
    let $sha := local:get-head-sha($repo)
    return if ($sha) then map {
      "sha": $sha,
      "url": $repo?host || "/" || $repo?account || "/" || $repo?reponame ||
        "/archive/" || $sha || ".zip"
    } else ()
  else (
    util:log-system-out("Not a github repo? " || $url)
  )
};
