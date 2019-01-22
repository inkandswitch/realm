module History exposing (History, empty, current, hasSeen, hasBack, hasForward, push, back, forward)

import List exposing (length, isEmpty)

{- NOTE: Allows going back to the empty state -}

type alias History a =
    { backward : List a
    , forward : List a
    , seen : List a
    }


uniqueAdd : a -> List a -> List a
uniqueAdd val list =
    if List.member val list then list else (val :: list)


empty : History a
empty =
    { backward = []
    , forward = []
    , seen = []
    }


current : History a -> Maybe a
current =
    .backward >> List.head


hasBack : History a -> Bool
hasBack =
    .backward >> ((not) << isEmpty)


hasForward : History a -> Bool
hasForward =
    .forward >> ((not) << isEmpty)


hasSeen : History a -> Bool
hasSeen =
    .seen >> ((not) << isEmpty)


push : a -> History a -> History a
push val history =
    { history
        | backward = val :: history.backward
        , forward = []
        , seen = (uniqueAdd val history.seen)
    }


back : History a -> History a
back history =
    case List.head history.backward of
        Just prevCurrent ->
            { history
                | backward = tailOrEmpty history.backward
                , forward = prevCurrent :: history.forward
            }
        Nothing ->
            history


forward : History a -> History a
forward history =
    case List.head history.forward of
        Just next ->
            { history
                | backward = next :: history.backward
                , forward = tailOrEmpty history.forward
            }
        Nothing ->
            history


tailOrEmpty : List a -> List a
tailOrEmpty list =
    Maybe.withDefault [] (List.tail list)