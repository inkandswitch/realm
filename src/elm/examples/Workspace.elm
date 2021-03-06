module Workspace exposing (Doc, Msg, State, gizmo)

import Browser.Dom as Dom
import Clipboard
import Colors
import Config
import Css exposing (..)
import Dict
import FarmUrl
import Gizmo exposing (Flags, Model)
import History exposing (History)
import Html.Styled as Html exposing (..)
import Html.Styled.Attributes as Attributes exposing (autofocus, css, placeholder, selected, value)
import Html.Styled.Events exposing (..)
import IO
import Json.Decode as D
import Json.Encode as E
import Keyboard exposing (Combo(..))
import Link
import ListSet exposing (ListSet)
import Navigation
import Repo
import Task
import Tooltip
import VsCode


gizmo : Gizmo.Program State Doc Msg
gizmo =
    Gizmo.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


type alias Error =
    ( String, String )


type Picker
    = OpenPicker (Maybe String)
    | CreatePicker
    | RendererPicker


{-| Ephemeral state not saved to the doc
-}
type alias State =
    { error : Maybe Error
    , activePicker : Maybe Picker
    }


type alias Pair =
    { code : String
    , data : String
    }


{-| Document state
-}
type alias Doc =
    { history : History String
    , codeDocs : ListSet String
    }


init : Flags -> ( State, Doc, Cmd Msg )
init flags =
    ( { error = Nothing
      , activePicker = Nothing
      }
    , { history = History.empty
      , codeDocs = ListSet.empty
      }
    , Cmd.none
    )


{-| Message type for modifying State and Doc inside update
-}
type Msg
    = NoOp
    | NavigateTo String
    | NavigateBack
    | NavigateForward
    | Create String
    | CreateDocCreated ( Repo.Ref, List String )
    | ToggleOpenPicker
    | ToggleCreatePicker
    | ToggleRendererPicker
    | HideActivePicker
    | Open String
    | Fork String
    | ForkWithNewData String
    | Edit String
    | ChangeRenderer String
    | CopyShareLink
    | Focus String
    | Blur String


update : Msg -> Model State Doc -> ( State, Doc, Cmd Msg )
update msg ({ state, doc } as model) =
    case Debug.log "update" msg of
        NoOp ->
            ( state
            , doc
            , Cmd.none
            )

        ChangeRenderer newCodeUrl ->
            case currentPair doc.history of
                Just { code, data } ->
                    if code /= newCodeUrl then
                        case FarmUrl.create { code = newCodeUrl, data = data } of
                            Ok newFarmUrl ->
                                update (NavigateTo newFarmUrl) model

                            Err err ->
                                update NoOp model

                    else
                        update NoOp model

                Nothing ->
                    update NoOp model

        NavigateTo url ->
            case FarmUrl.parse url of
                Ok pair ->
                    ( { state | activePicker = Nothing }
                    , { doc
                        | history = History.push url doc.history
                        , codeDocs = ListSet.insert pair.code doc.codeDocs
                      }
                    , IO.log <| "Navigating to  " ++ url
                    )

                Err err ->
                    ( { state | activePicker = Nothing, error = Just ( url, err ) }
                    , doc
                    , IO.log <| "Could not navigate to " ++ url ++ ". " ++ err
                    )

        NavigateBack ->
            ( { state | activePicker = Nothing }
            , { doc | history = History.back doc.history }
            , IO.log <| "Navigating backwards"
            )

        NavigateForward ->
            ( { state | activePicker = Nothing }
            , { doc | history = History.forward doc.history }
            , IO.log <| "Navigating forwards"
            )

        Create codeUrl ->
            ( state
            , doc
            , Repo.create ("WorkspaceCreate|" ++ codeUrl) 1
            )

        CreateDocCreated ( ref, urls ) ->
            case ( String.split "|" ref, urls ) of
                ( [ "WorkspaceCreate", codeUrl ], [ dataUrl ] ) ->
                    case FarmUrl.create { code = codeUrl, data = dataUrl } of
                        Ok farmUrl ->
                            update (NavigateTo farmUrl) model

                        _ ->
                            ( state
                            , doc
                            , IO.log "Failed to create a new gizmo"
                            )

                ( [ "CodeFork" ], [ codeUrl ] ) ->
                    currentPair doc.history
                        |> Result.fromMaybe "No current gizmo"
                        |> Result.andThen (\p -> FarmUrl.create { p | code = codeUrl })
                        |> Result.map
                            (\farmUrl ->
                                update (NavigateTo farmUrl) model
                                    |> withCmd (VsCode.open farmUrl)
                            )
                        |> Result.withDefault ( state, doc, Cmd.none )

                ( [ "CodeForkWithNewData" ], [ codeUrl ] ) ->
                    ( state
                    , doc
                    , Repo.createWithProps ("NewDataForCodeFork|" ++ codeUrl)
                        1
                        [ ( "title", E.string "My Data Doc" ) ]
                    )

                ( [ "NewDataForCodeFork", codeUrl ], [ dataUrl ] ) ->
                    FarmUrl.create { code = codeUrl, data = dataUrl }
                        |> Result.map
                            (\farmUrl ->
                                update (NavigateTo farmUrl) model
                                    |> withCmd (VsCode.open farmUrl)
                            )
                        |> Result.withDefault ( state, doc, Cmd.none )

                _ ->
                    ( state
                    , doc
                    , IO.log "Failed to create a new gizmo"
                    )

        HideActivePicker ->
            ( { state | activePicker = Nothing }
            , doc
            , Cmd.none
            )

        ToggleCreatePicker ->
            case Maybe.map isCreatePicker state.activePicker of
                Just True ->
                    update HideActivePicker model

                _ ->
                    ( { state | activePicker = Debug.log "set picker" (Just CreatePicker) }
                    , doc
                    , Cmd.none
                    )

        ToggleRendererPicker ->
            case Maybe.map isRendererPicker state.activePicker of
                Just True ->
                    update HideActivePicker model

                _ ->
                    ( { state | activePicker = Just RendererPicker }
                    , doc
                    , Cmd.none
                    )

        ToggleOpenPicker ->
            case Maybe.map isOpenPicker state.activePicker of
                Just True ->
                    update HideActivePicker model

                _ ->
                    ( { state | activePicker = Just (OpenPicker Nothing) }
                    , doc
                    , Cmd.none
                    )

        Open url ->
            update (NavigateTo url) model

        Fork url ->
            ( state, doc, Repo.fork "CodeFork" url )

        ForkWithNewData url ->
            ( state, doc, Repo.fork "CodeForkWithNewData" url )

        Edit url ->
            ( state, doc, VsCode.open url )

        CopyShareLink ->
            case History.current doc.history of
                Just url ->
                    ( state
                    , doc
                    , Clipboard.copy url
                    )

                Nothing ->
                    ( state
                    , doc
                    , IO.log <| "Nothing to copy"
                    )

        Focus id ->
            ( state
            , doc
            , Task.attempt (\_ -> NoOp) <| Dom.focus id
            )

        Blur id ->
            ( state
            , doc
            , Task.attempt (\_ -> NoOp) <| Dom.blur id
            )


withCmd : Cmd msg -> ( state, doc, Cmd msg ) -> ( state, doc, Cmd msg )
withCmd cmd ( state, doc, prevCmd ) =
    ( state, doc, Cmd.batch [ cmd, prevCmd ] )


view : Model State Doc -> Html Msg
view ({ flags, doc, state } as model) =
    div
        [ onClick HideActivePicker
        , on "navigate" (D.map NavigateTo detail)
        , css
            [ displayFlex
            , flexDirection column
            , height (vh 100)
            , width (vw 100)
            , position relative
            ]
        ]
        [ div
            [ css
                [ flexShrink (num 0)
                ]
            ]
            [ viewNavigationBar model
            ]
        , viewContent model
        ]


detail : D.Decoder String
detail =
    D.at [ "detail", "value" ] D.string


viewRendererPicker : Model State Doc -> Html Msg
viewRendererPicker { flags } =
    div
        [ on "select" (D.map ChangeRenderer detail)
        , css
            [ position absolute
            , top (pct 100)
            , right (px 0)
            , marginTop (px 10)
            , width (px 300)
            , zIndex (int 1)
            , before
                [ zIndex (int 2)
                , display block
                , position absolute
                , top (px -5)
                , width (px 10)
                , height (px 10)
                , right (px 10)
                , property "content" "''"
                , borderLeft3 (px 1) solid (hex "ccc")
                , borderTop3 (px 1) solid (hex "ccc")
                , backgroundColor (hex "fff")
                , property "transform" "rotate(45deg)"
                ]
            ]
        ]
        [ Gizmo.render Config.rendererPicker flags.data
        ]


viewOpenPicker : Model State Doc -> Html Msg
viewOpenPicker { flags } =
    div
        --[ on "select" (D.map NavigateTo detail)
        [ css
            [ position absolute
            , top (pct 100)
            , left (px 0)
            , marginTop (px 10)
            , width (px 300)
            , zIndex (int 1)
            , before
                [ zIndex (int 2)
                , display block
                , position absolute
                , top (px -5)
                , width (px 10)
                , height (px 10)
                , left (px 10)
                , property "content" "''"
                , borderLeft3 (px 1) solid (hex "ccc")
                , borderTop3 (px 1) solid (hex "ccc")
                , backgroundColor (hex "fff")
                , property "transform" "rotate(45deg)"
                ]
            ]
        ]
        [ Gizmo.render Config.openPicker flags.data
        ]


viewCreatePicker : Model State Doc -> Html Msg
viewCreatePicker { flags } =
    div
        [ on "select" (D.map Create detail)
        , css
            [ position absolute
            , top (pct 100)
            , left (px 0)
            , marginTop (px 10)
            , width (px 300)
            , zIndex (int 1)
            , backgroundColor (hex "fff")
            , before
                [ zIndex (int 2)
                , display block
                , position absolute
                , top (px -5)
                , width (px 10)
                , height (px 10)
                , left (px 10)
                , property "content" "''"
                , borderLeft3 (px 1) solid (hex "ccc")
                , borderTop3 (px 1) solid (hex "ccc")
                , backgroundColor (hex "fff")
                , property "transform" "rotate(45deg)"
                ]
            ]
        ]
        [ div [ css [ pickerStyle ] ]
            [ viewNewGizmo
            , Gizmo.render Config.createPicker flags.data
            ]
        ]


viewNavigationBar : Model State Doc -> Html Msg
viewNavigationBar ({ doc, state } as model) =
    div
        [ css
            [ displayFlex
            , alignItems center
            , boxShadow5 zero (px 2) (px 8) zero (rgba 0 0 0 0.12)
            , borderBottom3 (px 1) solid (hex "ddd")
            , height (px 40)
            ]
        ]
        [ viewNavButtons model
        , viewTitle model
        , viewSecondaryButtons doc
        ]


viewNavButtons : Model State Doc -> Html Msg
viewNavButtons ({ doc } as model) =
    div
        [ css
            [ alignItems start
            , justifyContent start
            , marginLeft (px 10)
            ]
        ]
        [ viewButton
            (History.hasBack doc.history)
            NavigateBack
            [ text "<"
            ]
        , viewButton
            (History.hasForward doc.history)
            NavigateForward
            [ text ">"
            ]
        , div
            [ css
                [ display inlineBlock
                , position relative
                ]
            ]
            [ viewLink
                True
                ToggleOpenPicker
                (Tooltip.tooltip Tooltip.BottomRight "Cmd+t")
                [ text "open"
                ]
            , case Maybe.map isOpenPicker model.state.activePicker of
                Just True ->
                    viewOpenPicker model

                _ ->
                    Html.text ""
            ]
        , div
            [ css
                [ display inlineBlock
                , position relative
                ]
            ]
            [ viewLink
                True
                ToggleCreatePicker
                (Tooltip.tooltip Tooltip.BottomRight "Cmd+n")
                [ text "new"
                ]
            , case Maybe.map isCreatePicker model.state.activePicker of
                Just True ->
                    viewCreatePicker model

                _ ->
                    Html.text ""
            ]
        ]


pickerStyle : Style
pickerStyle =
    batch
        [ boxShadow5 zero (px 2) (px 8) zero (rgba 0 0 0 0.12)
        , border3 (px 1) solid (hex "ddd")
        , borderRadius (px 5)
        , maxHeight (px 400)
        , overflowX hidden
        , overflowY auto
        ]


viewButton : Bool -> Msg -> List (Html Msg) -> Html Msg
viewButton isActive msg children =
    let
        style =
            if isActive then
                activeButtonStyle

            else
                inactiveButtonStyle
    in
    span
        [ stopPropagationOn "click" (D.succeed ( msg, isActive ))
        , css
            ([ display inlineBlock
             , borderRadius (px 3)
             , padding2 (px 3) (px 5)
             , fontWeight bold
             , marginRight (px 5)
             ]
                ++ style
            )
        ]
        children


viewNewGizmo =
    div
        [ css
            [ padding (px 10)
            , cursor pointer
            ]
        , onClick (ForkWithNewData Config.gizmoTemplate)
        ]
        [ text "+ Develop new Gizmo" ]


activeButtonStyle =
    [ cursor pointer
    , color (hex Colors.primary)
    , border3 (px 1) solid (hex Colors.primary)
    , hover
        [ color (hex Colors.darkerPrimary)
        , borderColor (hex Colors.darkerPrimary)
        ]
    ]


inactiveButtonStyle =
    [ cursor pointer
    , border3 (px 1) solid (hex "aaa")
    , color (hex "aaa")
    ]


viewSecondaryButtons : Doc -> Html Msg
viewSecondaryButtons doc =
    div
        [ css
            [ alignItems end
            , justifyContent end
            , marginRight (px 10)
            , textAlign right
            ]
        ]
        [ case currentPair doc.history of
            Nothing ->
                text ""

            Just { code } ->
                div
                    [ css
                        [ display inlineBlock
                        , position relative
                        ]
                    ]
                    [ viewLink
                        True
                        (Fork code)
                        (Tooltip.tooltip Tooltip.BottomLeft "Cmd+Shift+f")
                        [ text "fork"
                        ]
                    , case History.current doc.history of
                        Nothing ->
                            text ""

                        Just farmUrl ->
                            viewLink True
                                (Edit farmUrl)
                                (Tooltip.tooltip Tooltip.BottomLeft "Edit in VS Code")
                                [ text "edit" ]
                    ]
        , viewLink
            True
            CopyShareLink
            (Tooltip.tooltip Tooltip.BottomLeft "Cmd+s")
            [ text "share"
            ]
        ]


viewLink : Bool -> Msg -> List Style -> List (Html Msg) -> Html Msg
viewLink isActive msg tooltip children =
    let
        style =
            if isActive then
                activeLinkStyle

            else
                inactiveLinkStyle
    in
    span
        [ stopPropagationOn "click" (D.succeed ( msg, isActive ))
        , css
            ([ display inlineBlock
             , border zero
             , fontSize (Css.em 0.9)
             , padding (px 5)
             ]
                ++ tooltip
                ++ style
            )
        ]
        children


activeLinkStyle =
    [ cursor pointer
    , color (hex Colors.primary)
    , hover
        [ color (hex Colors.darkerPrimary)
        ]
    ]


inactiveLinkStyle =
    [ cursor pointer
    , border3 (px 1) solid (hex "aaa")
    , color (hex "aaa")
    ]


viewTitle : Model State Doc -> Html Msg
viewTitle ({ doc, state } as model) =
    div
        [ onStopPropagationClick NoOp
        , Keyboard.onPress Enter (Blur "title-input")
        , css
            [ flex (num 1)
            , alignItems center
            , justifyContent center
            , padding (px 5)
            , borderRadius (px 5)
            , color (hex "333")
            , margin2 (px 5) (px 5)
            , position relative
            , fontSize (Css.em 1.1)
            , displayFlex
            , hover
                [ color (hex "555")
                ]
            , pseudoClass "focus-within"
                [ color (hex "555")
                ]
            ]
        ]
        (case currentPair doc.history of
            Just { code, data } ->
                [ viewDataTitle data
                , viewRendererTitle model code
                ]

            Nothing ->
                [ div
                    [ css
                        [ margin2 (px 2) (px 0)
                        ]
                    ]
                    [ text <| String.fromChar '\u{00A0}'
                    ]
                ]
        )


viewDataTitle : String -> Html Msg
viewDataTitle dataUrl =
    viewLiveEdit "title" dataUrl


viewRendererTitle : Model State Doc -> String -> Html Msg
viewRendererTitle model codeUrl =
    div
        [ css
            [ flexShrink (int 0)
            ]
        ]
        [ span
            [ onClick ToggleRendererPicker
            , css
                [ color (hex "aaa")
                , fontSize (Css.em 0.8)
                , cursor pointer
                ]
            ]
            [ viewProperty "title" codeUrl
            ]
        , case Maybe.map isRendererPicker model.state.activePicker of
            Just True ->
                viewRendererPicker model

            _ ->
                Html.text ""
        ]


viewContent : Model State Doc -> Html Msg
viewContent { doc, state } =
    div
        [ css
            [ flex (num 1)
            , position relative
            , overflow auto
            , property "isolation" "isolate"
            ]
        ]
        [ case state.error of
            Just ( url, err ) ->
                text <| "'" ++ url ++ "' could not be parsed: " ++ err

            Nothing ->
                case currentPair doc.history of
                    Just ({ code, data } as pair) ->
                        Gizmo.render code data

                    Nothing ->
                        viewEmptyContent
        ]


viewEmptyContent : Html Msg
viewEmptyContent =
    div
        [ css
            [ lineHeight (num 1.2)
            , displayFlex
            , flexDirection column
            , alignItems center
            , color (hex "444")
            ]
        ]
        [ div
            [ css
                [ maxWidth (px 450)
                , padding (px 20)
                ]
            ]
            [ h1
                [ css
                    [ fontWeight bold
                    , fontSize (Css.em 1.3)
                    , marginBottom (px 15)
                    ]
                ]
                [ text "Welcome to Farm!"
                ]
            , p
                [ css
                    [ margin2 (px 10) (px 0)
                    ]
                ]
                [ text "Get started by opening an existing farm url using the "
                , span
                    [ onStopPropagationClick ToggleOpenPicker
                    , css
                        [ color (hex Colors.primary)
                        , cursor pointer
                        , hover
                            [ color (hex Colors.darkerPrimary)
                            ]
                        ]
                    ]
                    [ text "open menu"
                    ]
                , text " in the top left. Or you can create a new gizmo using the "
                , span
                    [ onStopPropagationClick ToggleCreatePicker
                    , css
                        [ color (hex Colors.primary)
                        , cursor pointer
                        , hover
                            [ color (hex Colors.darkerPrimary)
                            ]
                        ]
                    ]
                    [ text "create menu"
                    ]
                , text ", also in the top left!"
                ]
            ]
        ]


viewProperty : String -> String -> Html Msg
viewProperty prop url =
    Gizmo.renderWith [ Gizmo.attr "prop" prop ] Config.property url


viewLiveEdit : String -> String -> Html Msg
viewLiveEdit prop url =
    let
        props =
            [ Gizmo.attr "prop" prop
            , Gizmo.attr "input-id" "title-input"
            , Gizmo.attr "default" "No title"
            ]
    in
    Gizmo.renderWith props Config.liveEdit url


currentPair : History String -> Maybe Pair
currentPair =
    History.current
        >> Result.fromMaybe "No current url"
        >> Result.andThen FarmUrl.parse
        >> Result.toMaybe


currentCode : History String -> Maybe String
currentCode =
    currentPair
        >> Maybe.map (\{ code } -> code)


onStopPropagationClick : Msg -> Html.Attribute Msg
onStopPropagationClick msg =
    stopPropagationOn "click" (D.succeed ( msg, True ))


isOpenPicker : Picker -> Bool
isOpenPicker picker =
    case picker of
        OpenPicker _ ->
            True

        _ ->
            False


isRendererPicker : Picker -> Bool
isRendererPicker picker =
    case picker of
        RendererPicker ->
            True

        _ ->
            False


isCreatePicker : Picker -> Bool
isCreatePicker picker =
    case picker of
        CreatePicker ->
            True

        _ ->
            False


subscriptions : Model State Doc -> Sub Msg
subscriptions { state, doc } =
    Sub.batch
        [ Navigation.currentUrl NavigateTo
        , Repo.created CreateDocCreated
        , Keyboard.shortcuts
            [ ( Cmd O, ToggleOpenPicker )
            , ( Cmd T, ToggleOpenPicker )
            , ( Cmd (Shift F)
              , doc.history
                    |> currentCode
                    |> Maybe.map Fork
                    |> Maybe.withDefault NoOp
              )
            , ( Cmd I, ToggleRendererPicker )
            , ( Cmd S, CopyShareLink )
            , ( Cmd N, ToggleCreatePicker )
            , ( Cmd Left, NavigateBack )
            , ( Cmd Right, NavigateForward )
            , ( Ctrl O, ToggleOpenPicker )
            , ( Ctrl T, ToggleOpenPicker )
            , ( Ctrl S, CopyShareLink )
            , ( Ctrl I, ToggleRendererPicker )
            , ( Ctrl N, ToggleCreatePicker )
            , ( Ctrl Left, NavigateBack )
            , ( Ctrl Right, NavigateForward )
            , ( Esc, HideActivePicker )
            ]
        ]
