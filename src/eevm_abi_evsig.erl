-module(eevm_abi_evsig).
-export([getsig/2,decode/3,decode_auto/1]).
-export([local_dir/1,
         local_dir_then_fetchsig/1,
         fetchsig/1]).

decode_auto(<<Signature:4/binary,Data/binary>>) ->
  decode(Signature, Data, fun local_dir_then_fetchsig/1).

decode(Signature,Data,Getter) ->
    case getsig(Signature,Getter) of
        not_found ->
            not_found;
        {_, ABIIn, _} = ABI ->
            #{
              decode=>contract_evm_abi:decode_abi(Data, ABIIn),
              sig=>contract_evm_abi:mk_sig(ABI)
             };
        [Found|_] = _All ->
            {ok,{_, ABI, _}}=contract_evm_abi:parse_signature(Found),
            #{
              decode => contract_evm_abi:decode_abi(Data, ABI),
              sig=>Found
             }
    end.

getsig(<<221,242,82,173,27,226,200,155,105,194,176,104,252,55,141,170,149,43,167,241,99,196,161,22,40,245,90,77,245,35,179,239>>,_) ->
  {{function,<<"Transfer">>},
   [{<<"from">>,{indexed,address}},
    {<<"to">>,{indexed,address}},
    {<<"value">>,uint256}], undefined};

getsig(<<140,91,225,229,235,236,125,91,209,79,113,66,125,30,132,243,221,3,20,192,247,178,41,30,91,32,10,200,199,195,185,37>>,_) ->
  {{function,<<"Approval">>},
   [{<<"from">>,{indexed,address}},
    {<<"to">>,{indexed,address}},
    {<<"value">>,uint256}], undefined};

getsig(Any,Getter) ->
    Getter(Any).

local_dir_then_fetchsig(Any) ->
    case local_dir(Any) of
        not_found ->
            fetchsig(Any);
        Other ->
            Other
    end.

local_dir(Any) ->
  AbiS=lists:foldl(
         fun(Filename,false) ->
             try
               ABI=contract_evm_abi:parse_abifile(Filename),
               R=contract_evm_abi:find_event_hash(Any,ABI),
               case R of
                 [] ->
                   false;
                 [Event] ->
                   Event
               end
             catch Ec:Ee:S ->
                     io:format("~p:~p @ ~p~n",[Ec,Ee,S]),
                     false
             end;
             (_,A) -> A
         end, false,
         filelib:wildcard("*.abi")
        ),
  if(AbiS == false) ->
        not_found;
    true ->
      AbiS
  end.



%event Transfer(address indexed _from, address indexed _to, uint256 _value)
%event Approval(address indexed _owner, address indexed _spender, uint256 _value)

fetchsig(Sig) ->
  %curl https://www.4byte.directory/api/v1/event-signatures/\?hex_signature=0xBA6B0A89802623C9DB933568CE2F64B9D820F2243C46F0B10C4044E449AF3FC5 | jq '.results'
  io:format("~p~n",[Sig]),
  URL=case size(Sig) of
          4 ->
              list_to_binary(["/api/v1/signatures/?hex_signature=0x",binary:encode_hex(Sig)]);
          32 ->
              list_to_binary(["/api/v1/event-signatures/?hex_signature=0x",binary:encode_hex(Sig)])
      end,
  case tpapi2:httpget("https://www.4byte.directory", URL) of
    #{<<"count">>:=0} ->
      not_found;
    #{<<"count">>:=_,<<"results">>:=R} ->
      [ TS || #{<<"text_signature">>:=TS} <- R ]
  end.

