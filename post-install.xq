xquery version "3.1";

import module namespace config = "http://dracor.org/ns/exist/v1/config" at "modules/config.xqm";

(: The following external variables are set by the repo:deploy function :)
(: the target collection into which the app is deployed :)
declare variable $target external;

declare function local:store($file-path, $content) {
  let $segments := tokenize($file-path, "/")
  let $name := $segments[last()]
  let $col := substring(
    $file-path,
    1,
    string-length($file-path) - string-length($name) - 1
  )
  return xmldb:store($col, $name, $content)
};

(:
 : Set the child element $name of $parent to the value of the environment
 : variable $var. A missing element is added. If the variable is not set (or
 : empty) the stored value is kept. The value is not logged since it may be a
 : secret.
 :)
declare function local:set-from-env(
  $parent as element(),
  $name as xs:string,
  $var as xs:string
) as empty-sequence() {
  let $value := environment-variable($var)
  let $element := $parent/*[local-name() = $name]
  return if (not($value)) then (
  ) else if ($element) then (
    util:log-system-out("Setting " || $name || " from " || $var),
    update value $element with $value
  ) else (
    util:log-system-out("Adding " || $name || " from " || $var),
    update insert element {$name} { $value } into $parent
  )
};

(:
 : The config file is created with default values on the first install. On
 : every install the values are then updated from the following environment
 : variables, as far as they are set:
 :
 : - DRACOR_API_BASE: base URI the DraCor API will be available under
 : (default: https://dracor.org/api/v1)
 : - DRACOR_ID_BASE: base of identifier URIs (optional, defaults to
 : https://dracor.org/id; only needed for installations publishing their
 : own corpora)
 : - FUSEKI_SERVER: base URI of the fuseki server
 : (default: http://localhost:3030/dracor/)
 : - METRICS_SERVER: DraCor metrics service URI
 : (default: http://localhost:8030/metrics/)
 : - DRACOR_SYNC_DELAY: delay in seconds before derived data is synced after a
 : change (optional, defaults to 10)
 :
 : The API itself cannot read these variables: environment-variable() returns
 : nothing for non-DBA users.
 :)
declare function local:update-config-file() as item()* {
  if (doc($config:file)/config) then (
  ) else (
    util:log-system-out("Creating " || $config:file),
    local:store(
      $config:file,
      <config>
        <api-base>https://dracor.org/api/v1</api-base>
        <services>
          <fuseki>http://localhost:3030/dracor/</fuseki>
          <metrics>http://localhost:8030/metrics/</metrics>
        </services>
      </config>
    )
  ),
  if (doc($config:file)/config/services) then (
  ) else (
    update insert <services /> into doc($config:file)/config
  ),
  local:set-from-env(doc($config:file)/config, "api-base", "DRACOR_API_BASE"),
  local:set-from-env(doc($config:file)/config, "id-base", "DRACOR_ID_BASE"),
  local:set-from-env(
    doc($config:file)/config,
    "sync-delay",
    "DRACOR_SYNC_DELAY"
  ),
  local:set-from-env(
    doc($config:file)/config/services,
    "fuseki",
    "FUSEKI_SERVER"
  ),
  local:set-from-env(
    doc($config:file)/config/services,
    "metrics",
    "METRICS_SERVER"
  )
};

(:
 : The secrets file is created on the first install and updated on every
 : install from the following environment variables, as far as they are set:
 :
 : - GITHUB_WEBHOOK_SECRET: secret for the GitHub webhook
 : - FUSEKI_SECRET: admin password for the fuseki server
 :)
declare function local:update-secrets-file() as item()* {
  if (doc($config:secrets-file)/secrets) then (
  ) else (
    util:log-system-out("Creating " || $config:secrets-file),
    local:store(
      $config:secrets-file,
      <secrets><fuseki /><gh-webhook /></secrets>
    )
  ),
  (: FIXME: find a better solution to protect the webhook secret :)
  sm:chmod(xs:anyURI($config:secrets-file), "rw-------"),
  local:set-from-env(
    doc($config:secrets-file)/secrets,
    "fuseki",
    "FUSEKI_SECRET"
  ),
  local:set-from-env(
    doc($config:secrets-file)/secrets,
    "gh-webhook",
    "GITHUB_WEBHOOK_SECRET"
  )
};

(: elevate privileges for github webhook :)
let $webhook := xs:anyURI($target || "/modules/webhook.xqm")
let $sitelinks-job := xs:anyURI($target || "/jobs/sitelinks.xq")
(: allows running the reconcile job from the scheduler in conf.xml :)
let $reconcile-job := xs:anyURI($target || "/jobs/reconcile.xq")

(: register the RESTXQ module :)
let $restxq-module := xs:anyURI("modules/api.xpm")

return (
  local:update-config-file(),
  local:update-secrets-file(),
  sm:chown($webhook, "admin"),
  sm:chgrp($webhook, "dba"),
  sm:chmod($webhook, "rwsr-xr-x"),
  sm:chown($sitelinks-job, "admin"),
  sm:chgrp($sitelinks-job, "dba"),
  sm:chmod($sitelinks-job, "rwsr-xr-x"),
  sm:chown($reconcile-job, "admin"),
  sm:chgrp($reconcile-job, "dba"),
  sm:chmod($reconcile-job, "rwsr-xr-x"),
  exrest:register-module($restxq-module),
  (: sync what may have been missed while the app was not installed :)
  scheduler:schedule-xquery-periodic-job(
    $reconcile-job,
    1,
    (: not prefixed with sync-, which would count it as pending sync :)
    "reconcile",
    <parameters />,
    60000,
    0
  )
)
