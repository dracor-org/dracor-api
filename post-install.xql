xquery version "3.0";

(: The following external variables are set by the repo:deploy function :)

(: the target collection into which the app is deployed :)
declare variable $target external;

let $restxq-module := xs:anyURI('modules/api.xpm')

(: elevate privileges for github webhook :)
let $webhook := $target || '/github-webhook.xq'
return (
  exrest:register-module($restxq-module),
  sm:chown(xs:anyURI($webhook), "admin"),
  sm:chgrp(xs:anyURI($webhook), "dba"),
  sm:chmod(xs:anyURI($webhook), 'rwsr-xr-x')
)
