port module Repo exposing (Props, Ref, Url, clone, create, createWithProps, created, docs, fork, open, rawDocs)

import Doc exposing (Doc, RawDoc)
import Json.Decode as D
import Json.Encode as E
import Result
import Task


type alias Url =
    String


type alias Ref =
    String


type alias Props =
    List ( String, E.Value )


port created : (( Ref, List Url ) -> msg) -> Sub msg


port rawDocs : (( Url, RawDoc ) -> msg) -> Sub msg


docs : (( Url, Doc ) -> msg) -> Sub msg
docs mkMsg =
    rawDocs (Tuple.mapSecond Doc.decode)
        |> Sub.map mkMsg


create : Ref -> Int -> Cmd msg
create ref n =
    createWithProps ref n []


createWithProps : Ref -> Int -> Props -> Cmd msg
createWithProps ref n props =
    send <| Create ref n props


open : Url -> Cmd msg
open url =
    send <| Open url


clone : Ref -> Url -> Cmd msg
clone ref url =
    send <| Clone ref url


fork : Ref -> Url -> Cmd msg
fork ref url =
    send <| Fork ref url



-- type alias Model msg =
--     { createQ : List (List String -> msg)
--     }
-- type Msg
--     = Created (List String)
--     | Error String


port repoOut : E.Value -> Cmd msg



-- update : Msg -> Model msg -> ( Model msg, Cmd msg )
-- update msg model =
--     case msg of
--         Created ids ->
--             case model.createQ of
--                 mkMsg :: createQ ->
--                     ( { model | createQ = createQ }, mkMsg ids |> Task.succeed |> Task.perform identity )
-- Outgoing Messages


type OutMsg
    = Create Ref Int Props -- String ref and number of docs to create
    | Clone Ref Url -- String ref and url of document
    | Fork Ref Url -- String ref and url of document to fork
    | Open Url


encodeOut : OutMsg -> E.Value
encodeOut msg =
    case msg of
        Create ref n props ->
            E.object
                [ ( "t", E.string "Create" )
                , ( "ref", E.string ref )
                , ( "n", E.int n )
                , ( "p", E.object props )
                ]

        Fork ref url ->
            E.object
                [ ( "t", E.string "Fork" )
                , ( "ref", E.string ref )
                , ( "url", E.string url )
                ]

        Clone ref url ->
            E.object
                [ ( "t", E.string "Clone" )
                , ( "ref", E.string ref )
                , ( "url", E.string url )
                ]

        Open url ->
            E.object
                [ ( "t", E.string "Open" )
                , ( "url", E.string url )
                ]


send : OutMsg -> Cmd msg
send =
    encodeOut >> repoOut



-- Incoming Messages
-- port repoIn : (D.Value -> msg) -> Sub msg
-- msgDecoder : D.Decoder Msg
-- msgDecoder =
--     D.field "t" D.string
--         |> D.andThen typeDecoder
-- typeDecoder : String -> D.Decoder Msg
-- typeDecoder t =
--     case t of
--         "Created" ->
--             D.map Created
--                 (D.field "ids" (D.list D.string))
--         _ ->
--             D.fail "Not a valid Repo.Msg type."
-- decodeMsg : D.Value -> Msg
-- decodeMsg val =
--     case D.decodeValue msgDecoder val of
--         Err err ->
--             Error (D.errorToString err)
--         Ok msg ->
--             msg
-- incoming : Sub Msg
-- incoming =
--     repoIn decodeMsg
