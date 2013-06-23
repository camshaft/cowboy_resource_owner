-module(cowboy_resource_owner).

-export([execute/2]).
-export([client_id/1]).
-export([owner_id/1]).
-export([scopes/1]).
-export([is_authenticated/1]).
-export([is_authorized/2]).

-record (resource_auth, {
  client_id :: binary(),
  owner_id :: binary(),
  expiration :: calendar:datetime(),
  scopes :: [binary()],
  other :: term()
}).

execute(Req, Env) ->
  Value = case get_token(Req) of
    undefined ->
      undefined;
    Token ->
      case handle_token(Token, Env) of
        {ClientID, OwnerID, Scopes, Expiration, Other} ->
          #resource_auth{client_id = ClientID,
                         owner_id = OwnerID,
                         scopes = Scopes,
                         expiration = Expiration,
                         other = Other};
        {error, _} = Error ->
          Error;
        _ ->
          {error, invalid_token}
      end
  end,
  Req2 = cowboy_req:set_meta(resource_auth, Value, Req),
  {ok, Req2, Env}.

client_id(Req) ->
  {Info, Req} = cowboy_req:meta(resource_auth, Req),
  case Info of
    {error, _} = Error -> Error;
    #resource_auth{client_id = ClientID} -> ClientID;
    _ -> {error, invalid_token_info}
  end.

owner_id(Req) ->
  {Info, Req} = cowboy_req:meta(resource_auth, Req),
  case Info of
    {error, _} = Error -> Error;
    #resource_auth{owner_id = OwnerID} -> OwnerID;
    _ -> {error, invalid_token_info}
  end.

scopes(Req) ->
  {Info, Req} = cowboy_req:meta(resource_auth, Req),
  case Info of
    {error, _} = Error -> Error;
    #resource_auth{scopes = Scopes} -> Scopes;
    _ -> {error, invalid_token_info}
  end.

is_authenticated(Req) ->
  case owner_id(Req) of
    ID when is_binary(ID) orelse is_integer(ID) -> true;
    _ -> false
  end.

is_authorized(RequiredScope, Req) when is_binary(RequiredScope) ->
  is_authorized([RequiredScope], Req);
is_authorized(RequiredScopes, Req) when is_list(RequiredScopes) ->
  OwnerScopes = scopes(Req),
  check_scopes(RequiredScopes, gb_sets:from_list(OwnerScopes)).

check_scopes([], _) ->
  true;
check_scopes([RequiredScope|RequiredScopes], OwnerScopes) ->
  case gb_sets:is_member(RequiredScope, OwnerScopes) of
    false ->
      false;
    true ->
      check_scopes(RequiredScopes, OwnerScopes)
  end.

%% TODO add more ways to authenticate
get_token(Req) ->
  case cowboy_req:parse_header(<<"authorization">>, Req) of
    {ok, {<<"bearer">>, AccessToken}, _} ->
      AccessToken;
    _ ->
      undefined
  end.

handle_token(Token, Env) ->
  case key(token_handler, Env) of
    undefined ->
      undefined;
    TokenHandler ->
      TokenHandler:handle(Token, Env)
  end.

key(Key, List) ->
  {_, Value} = lists:keyfind(Key, 1, List),
  Value.
