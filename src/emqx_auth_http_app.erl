%% Copyright (c) 2013-2019 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(emqx_auth_http_app).

-behaviour(application).
-behaviour(supervisor).

-emqx_plugin(auth).

-include("emqx_auth_http.hrl").

-export([ start/2
        , stop/1
        ]).
-export([init/1]).

%%--------------------------------------------------------------------
%% Application Callbacks
%%--------------------------------------------------------------------

start(_StartType, _StartArgs) ->
    with_env(auth_req, fun load_auth_hook/1),
    with_env(acl_req,  fun load_acl_hook/1),
    emqx_auth_http_cfg:register(),
	init_ets(),
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init_ets()->
	ets:new(failed_client, [set, public, named_table]),
	ets:new(blocked_client, [set, public, named_table]),
	ets:new(auth_config, [set, public, named_table]).

load_auth_hook(AuthReq) ->
    emqx_auth_http:register_metrics(),
    SuperReq = r(application:get_env(?APP, super_req, undefined)),
	ConfigReq = r(application:get_env(?APP, config_req, undefined)),
    HttpOpts = application:get_env(?APP, http_opts, []),
    RetryOpts = application:get_env(?APP, retry_opts, []),
    Params = #{auth_req => AuthReq,
               super_req => SuperReq,
			   config_req => ConfigReq,
               http_opts => HttpOpts,
               retry_opts => maps:from_list(RetryOpts)},
    emqx:hook('client.authenticate', fun emqx_auth_http:check/2, [Params]).

load_acl_hook(AclReq) ->
    emqx_acl_http:register_metrics(),
    HttpOpts = application:get_env(?APP, http_opts, []),
    RetryOpts = application:get_env(?APP, retry_opts, []),
    Params = #{acl_req => AclReq,
               http_opts => HttpOpts,
               retry_opts => maps:from_list(RetryOpts)},
    emqx:hook('client.check_acl', fun emqx_acl_http:check_acl/5, [Params]).

stop(_State) ->
    emqx:unhook('client.authenticate', fun emqx_auth_http:check/2),
    emqx:unhook('client.check_acl', fun emqx_acl_http:check_acl/5),
    emqx_auth_http_cfg:unregister().

%%--------------------------------------------------------------------
%% Dummy supervisor
%%--------------------------------------------------------------------

init([]) ->
    {ok, { {one_for_all, 10, 100}, []} }.

%%--------------------------------------------------------------------
%% Internel functions
%%--------------------------------------------------------------------

with_env(Par, Fun) ->
    case application:get_env(?APP, Par) of
        undefined -> ok;
        {ok, Req} -> Fun(r(Req))
    end.

r(undefined) ->
    undefined;
r(Config) ->
    Method = proplists:get_value(method, Config, post),
    Url    = proplists:get_value(url, Config),
    Params = proplists:get_value(params, Config),
	CacheTime = proplists:get_value(cache_time, Config),
	AppIds = proplists:get_value(appids, Config),
	LimitConfig = proplists:get_value(limit, Config),
    #http_request{method = Method, url = Url, params = Params, cache_time=CacheTime, appids=AppIds, limit_config=LimitConfig}.

