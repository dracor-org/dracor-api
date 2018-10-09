xquery version "3.0";

(: The following external variables are set by the repo:deploy function :)

(: the target collection into which the app is deployed :)
declare variable $target external;

let $restxq-module := xs:anyURI('modules/api.xpm')

(: elevate privileges for github webhook :)
let $webhook := xs:anyURI($target || '/github-webhook.xq')
let $sitelinks-job := xs:anyURI($target || '/jobs/sitelinks.xq')
return (
  sm:chown($webhook, "admin"),
  sm:chgrp($webhook, "dba"),
  sm:chmod($webhook, 'rwsr-xr-x'),
  sm:chown($sitelinks-job, "admin"),
  sm:chgrp($sitelinks-job, "dba"),
  sm:chmod($sitelinks-job, 'rwsr-xr-x'),
  exrest:register-module($restxq-module)
)
