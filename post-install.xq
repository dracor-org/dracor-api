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
 : Set a setting in an existing config file from an environment variable, so
 : that the variable takes effect on servers set up before it existed.
 :)
declare function local:update-setting(
  $name as xs:string,
  $variable as xs:string
) as empty-sequence() {
  let $value := environment-variable($variable)
  let $config := doc($config:file)/config
  let $setting := $config/*[local-name() = $name]
  return if (not($value)) then (
  ) else if ($setting) then (
    util:log-system-out("Setting " || $name || " to " || $value),
    update value $setting with $value
  ) else (
    util:log-system-out("Adding " || $name || " " || $value),
    update insert element {$name} { $value } into $config
  )
};

(:
 : We create an initial config file the values of which can be passed by the
 : following environment variables:
 :
 : - DRACOR_API_BASE: base URI the DraCor API will be available under
 : - DRACOR_ID_BASE: base of identifier URIs (optional, defaults to
 : https://dracor.org/id; only needed for installations publishing their
 : own corpora)
 : - FUSEKI_SERVER: base URI of the fuseki server
 : - METRICS_SERVER: DraCor metrics service URI
 : - DRACOR_SYNC_DELAY: delay in seconds before derived data is synced after a
 : change (optional, defaults to 30)
 :
 : If the config file already exists, only the identifier base and the sync
 : delay are updated from DRACOR_ID_BASE and DRACOR_SYNC_DELAY (when set).
 :)
declare function local:create-config-file() as item()? {
  if (doc($config:file)/config) then (
    util:log-system-out("Config file exists at " || $config:file),
    local:update-setting("id-base", "DRACOR_ID_BASE"),
    local:update-setting("sync-delay", "DRACOR_SYNC_DELAY")
  ) else (
    util:log-system-out("Creating " || $config:file),
    local:store(
      $config:file,
      <config>
        <api-base>
          {
            if (environment-variable("DRACOR_API_BASE")) then
              environment-variable("DRACOR_API_BASE")
            else
              "https://dracor.org/api/v1"
          }
        </api-base>
        {
          if (environment-variable("DRACOR_ID_BASE")) then
            <id-base>{ environment-variable("DRACOR_ID_BASE") }</id-base>
          else (
          )
        }
        {
          if (environment-variable("DRACOR_SYNC_DELAY")) then
            <sync-delay>
              { environment-variable("DRACOR_SYNC_DELAY") }
            </sync-delay>
          else (
          )
        }
        <services>
          <fuseki>
            {
              if (environment-variable("FUSEKI_SERVER")) then
                environment-variable("FUSEKI_SERVER")
              else
                "http://localhost:3030/dracor/"
            }
          </fuseki>
          <metrics>
            {
              if (environment-variable("METRICS_SERVER")) then
                environment-variable("METRICS_SERVER")
              else
                "http://localhost:8030/metrics/"
            }
          </metrics>
        </services>
      </config>
    )
  )
};

(:
 : We create an initial config file the values of which can be passed by the
 : following environment variables:
 :
 : - GITHUB_WEBHOOK_SECRET: secret for the GitHub webhook
 : - FUSEKI_SECRET: admin password for the fuseki server
 :)
declare function local:create-secrets-file() as item()? {
  if (doc($config:secrets-file)/secrets) then (
    util:log-system-out("Secrets file exists at " || $config:secrets-file)
  ) else (
    util:log-system-out("Creating " || $config:secrets-file),
    local:store(
      $config:secrets-file,
      <secrets>
        <fuseki>{ environment-variable("FUSEKI_SECRET") }</fuseki>
        <gh-webhook>
          { environment-variable("GITHUB_WEBHOOK_SECRET") }
        </gh-webhook>
      </secrets>
    ),
    (: FIXME: find a better solution to protect the webhook secret :)
    sm:chmod(xs:anyURI($config:secrets-file), "rw-------")
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
  local:create-config-file(),
  local:create-secrets-file(),
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
