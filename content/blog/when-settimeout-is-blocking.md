+++
title = "When `setTimeout` is a blocking call after all"
date = 2023-07-09
+++

I've spent my spare time over the last few days porting some React Native components to the web for an open source product I use. One of them was an autocomplete component built on top of the [Downshift](https://www.downshift-js.com) library. These React Native components were old, which meant they were class components; in turn, this meant the legacy [`downshift.js`](https://github.com/downshift-js/downshift/blob/20314b5f560921b8e762790dfa45386bf7916a54/src/downshift.js) class component was in use.

So I'm humming along getting all these React Native components running on the web, and suddenly I run into some strange behavior. In macOS Safari with mouse + keyboard the autocomplete component was working great; click one of the autocomplete options and it would immediately close the autocomplete interface and place your selection in the input field. In iOS Safari, however, there was a significant delay between tapping an autocomplete selection and the resulting action being taken. It made the interface feel laggy and it made for an unpleasant experience.

Delayed reponses to web touch interactions aren't necessarily strange on iOS; many of us are familiar with [Safari's tendency to delay click events by 300ms](https://stackoverflow.com/questions/12238587/eliminate-300ms-delay-on-click-events-in-mobile-safari). This gives WebKit the chance to determine between a single tap (click a field) and a double-tap (zoom in to the web page). I immediately suspected this was involved in the tap delay I was experiencing in the autocomplete component, and I started applying some of the known workarounds. Strangely, none of them were successful in eliminating the delay. That's when I realized zoom was already disabled for the entire SPA via a `user-scalable=no` viewport tag, so my guess was wrong. Something else had to be introducing the delay.

What could it be though? I started to investigate the event handlers registered on the autocomplete suggestion items. The two important ones turned out to be `onMouseMove` and `onClick`, both provided by the Downshift library. I wrapped their event handlers in my own closures, added some logging, and lo and behold:

```
20:18:35.334 mousemove event fired
20:18:35.604 onclick fired
```

The `click` event was consistently being fired on the element ~250ms _after_ the `mousemove` event was, but _only in iOS Safari when being tapped_. On macOS Safari the `click` event was fired immediately after the `mousemove` event as expected.

Ok, I thought, so maybe the Downshift library is doing something weird on mobile that's intentionally introducing the delay here. I cracked open the source code to take a peek.

[Here's the `mousemove` handler they provide](https://github.com/downshift-js/downshift/blob/20314b5f560921b8e762790dfa45386bf7916a54/src/downshift.js#L930-L944) for you to set on your autocomplete suggestion elements:

```js
onMouseMove: callAllEventHandlers(onMouseMove, () => {
  if (index === this.getState().highlightedIndex) {
    return
  }
  this.setHighlightedIndex(index, {
    type: stateChangeTypes.itemMouseEnter,
  })

  // We never want to manually scroll when changing state based
  // on `onMouseMove` because we will be moving the element out
  // from under the user which is currently scrolling/moving the
  // cursor
  this.avoidScrolling = true
  this.internalSetTimeout(() => (this.avoidScrolling = false), 250)
}),
```

Okkkk, not exactly what I was hoping to find. Everything here is pretty straightforward; there's a state change and a variable update. It sets `this.avoidScrolling` to `true`, along with a timeout that sets it back to `false` 250ms later... wait! We saw above that the delay between `mousemove` and `click` events was ~250ms. It must be blocking something on the value of `avoidScrolling`?

...turns out it is not doing anything with the value of `avoidScrolling` that would block the `onclick` event from being fired. That doesn't make any sense though. We know the 250ms timeout lines up perfectly with the delay between events that we're seeing. We also know that `setTimeout` is a non-blocking call.

Or... do we?

I added one more log:

```
20:18:35.334 mousemove event fired
20:18:35.598 settimeout callback fired
20:18:35.604 onclick fired
```

_What._

[MDN says](https://developer.mozilla.org/en-US/docs/Web/API/setTimeout#working_with_asynchronous_functions):

> setTimeout() is an asynchronous function, meaning that the timer function will not pause execution of other functions in the functions stack. In other words, you cannot use setTimeout() to create a "pause" before the next function in the function stack fires.

Now listen, I'm not generally in the business of arguing with MDN. A quick Google search for "settimeout blocking react component events" returned a list of results that were utterly unrelated to that entire line of thought. I couldn't deny the 250ms timeout was somehow involved in what was going on, but I spent hours digging into React and the Downshift library itself under the impression that I was more likely to find the cause of the problem there than I was trying to find a way to blame `setTimeout` for delaying the `click` event from firing.

When those investigations proved fruitless, I tried a new test setup: dropping Downshift's `mousemove` handler entirely for one of my own. I added my own `setTimeout` call:

```js
onMouseMove={_ => {
    console.log("mousemove event fired");
    setTimeout(() => {
        console.log("settimeout callback fired");
    }, 250);
}}
```

I was *shocked* to find out that this still triggered the same delay behavior from before:

```
20:18:35.334 mousemove event fired
20:18:35.598 settimeout callback fired
20:18:35.604 onclick fired
```

This is as simple as it gets. The `setTimeout` callback is running nothing but `console.log`. There are no external dependencies. How on earth is this stopping the `click` event from firing until after the callback executes?

I played around with the timeout value. `250ms` -> `100ms` decreased the delay accordingly. `250ms` -> `300ms` increased it. Oddly enough, setting it to 5000ms made the delay go away? So did 500ms. Eventually I narrowed it down: setting a timeout duration of `400ms` or less in the `mousemove` handler would prevent the `click` event from being fired until after the `setTimeout` callback finished executing, while a duration of `401ms` or more would have no such effect.

At this point I knew enough to be able to get around the behavior in a couple of different ways, but I was intensely curious about what was going on here. No amount of "400ms settimeout blocking events" or "settimeout mousemove blocks click event" was turning up anything at all on Google. I cloned `WebKit` (which took a _hot_ minute) and started poking around there to see if I could find anything. A search for "400ms" immediately turned up a very interesting layout test, [`LayoutTests/fast/events/touch/ios/content-observation/400ms-hover-intent.html`](https://github.com/WebKit/WebKit/blob/e7780d735de3975ec8bf854e4ed70d07c7648497/LayoutTests/fast/events/touch/ios/content-observation/400ms-hover-intent.html), containing the following code:

```js
tapthis.addEventListener("mousemove", function( event ) {
    setTimeout(function() {
        becomesVisible.style.display = "block";
        if (window.testRunner)
             testRunner.notifyDone();
    }, 400);
}, false);

// ...

tapthis.addEventListener("click", function( event ) {   
    result.innerHTML = "clicked";
}, false);
```

Exciting! This is the first piece of content I've been able to find that seems relevant to the behavior I'm encountering. Just like I found, this test case calls `setTimeout` with a 400ms delay value in the `mousemove` event handler, and, just like I found, this results in the `click` event handler for that same element...

_not being fired at all??_

Wait, that's not right. The `click` event should still fire, albeit delayed. Why is it not firing?

I couldn't immediately answer this question, so I went back to digging through search results for "400ms". I stumbled upon [this constant in `Source/WebCore/page/ios
/ContentChangeObserver.cpp`](https://github.com/WebKit/WebKit/blob/e7780d735de3975ec8bf854e4ed70d07c7648497/Source/WebCore/page/ios/ContentChangeObserver.cpp#L48):

```cpp
static const Seconds maximumDelayForTimers { 400_ms };
```

This was the key to the door I needed opened. _Content change observation_. Now we can get to the bottom of what's going on here.

Mouse and keyboard users have an advantage: hover and click are two separate, distinct actions. The user has full control over the timing of both, and they can wait to see the results of the first action (hover) before performing the second (click).

Touchscreen users have no such ability. For them, hover and click _are the same action_: technically hovering doesn't exist at all, but because not firing `mousemove` events would break the parts of the web that are designed around them, mobile browsers choose to fire both events when the user taps the screen. This leads to a unique challenge: there are cases where websites use the `mousemove` event as a trigger to change page content. Think showing a tooltip, or maybe a hover menu. Consider the following example from a [popular forums site](https://www.spigotmc.org):

{{ video_as_gif(src="/media/content_observation_example.mov") }}

The navbar has dropdown menu components that reveal on hover to provide access to a variety of different routes. The elements you hover over to reveal these dropdown menus, however, are also themselves clickable, taking you to the main route for that menu. On desktop you can mouse over one of the menu buttons, click it once, and go to the main route. On mobile with a touchscreen, however, the first tap reveals the dropdown menu (the hover action), and the second tap navigates to the main route (the click action). This is the browser using **content observation** to take your single tap action and turn it into two: hover, and click.

WebKit can't get away with requiring two taps on every clickable element to account for the possibility that they have a meaningful hover action. Content observation helps compensate for this; WebKit can observe what happens in the `mousemove` event handler after it's fired. If the handler modifies the DOM in any way, WebKit can decide to block the `click`; if the handler does not modify the DOM WebKit can allow the click event to be fired. Generally all of this observation logic can happen quickly enough that it's unnoticeable; `setTimeout`, however, introduces the unfortunate possibility that a `mousemove` event could modify the DOM hundreds of milliseconds after the event handler itself has finished executing, causing WebKit to fire a `click` event for a tap action that should have been left as a hover.

So what does WebKit do? Well of course, wait for the `setTimeout` callback to finish executing to be able to observe what it does, as long as the `setTimeout` delay value isn't greater than 400ms. Check out the [`DOMTimer::install` implementation](https://github.com/WebKit/WebKit/blob/e7780d735de3975ec8bf854e4ed70d07c7648497/Source/WebCore/page/DOMTimer.cpp#L188-L213):

```cpp
int DOMTimer::install(ScriptExecutionContext& context, Function<void(ScriptExecutionContext&)>&& action, Seconds timeout, bool oneShot)
{
    Ref<DOMTimer> timer = adoptRef(*new DOMTimer(context, WTFMove(action), timeout, oneShot));
    timer->suspendIfNeeded();
    timer->makeOpportunisticTaskDeferralScopeIfPossible(context);

    // Keep asking for the next id until we're given one that we don't already have.
    do {
        timer->m_timeoutId = context.circularSequentialID();
    } while (!context.addTimeout(timer->m_timeoutId, timer.get()));

    InspectorInstrumentation::didInstallTimer(context, timer->m_timeoutId, timeout, oneShot);

    // Keep track of nested timer installs.
    if (NestedTimersMap* nestedTimers = NestedTimersMap::instanceForContext(context))
        nestedTimers->add(timer->m_timeoutId, timer.get());
#if ENABLE(CONTENT_CHANGE_OBSERVER)
    if (is<Document>(context)) {
        auto& document = downcast<Document>(context);
        document.contentChangeObserver().didInstallDOMTimer(timer.get(), timeout, oneShot);
        if (DeferDOMTimersForScope::isDeferring())
            document.domTimerHoldingTank().add(timer.get());
    }
#endif
    return timer->m_timeoutId;
}
```

This is the code that handles `setTimeout` calls. There's a bit towards the end there that calls [`document.contentChangeObserver().didInstallDOMTimer(timer.get(), timeout, oneShot)`](https://github.com/WebKit/WebKit/blob/e7780d735de3975ec8bf854e4ed70d07c7648497/Source/WebCore/page/ios/ContentChangeObserver.cpp#L302-L320):

```cpp
void ContentChangeObserver::didInstallDOMTimer(const DOMTimer& timer, Seconds timeout, bool singleShot)
{
    if (!isContentChangeObserverEnabled())
        return;
    if (!isObservingContentChanges())
        return;
    if (!isObservingDOMTimerScheduling())
        return;
    if (hasVisibleChangeState())
        return;
    if (m_document.activeDOMObjectsAreSuspended())
        return;
    if (timeout > maximumDelayForTimers || !singleShot)
        return;
    LOG_WITH_STREAM(ContentObservation, stream << "didInstallDOMTimer: register this timer: (" << &timer << ") and observe when it fires.");

    registerDOMTimer(timer);
    adjustObservedState(Event::InstalledDOMTimer);
}
```

We can make note of the fact that the code bails if the `timeout` value is greater than `maximumDelayForTimers`, grounding our earlier discovery that values of `401ms` and above avoid triggering this behavior.

The code [adds the timer to a list](https://github.com/WebKit/WebKit/blob/e7780d735de3975ec8bf854e4ed70d07c7648497/Source/WebCore/page/ios/ContentChangeObserver.cpp#L359-L362):

```cpp
void ContentChangeObserver::registerDOMTimer(const DOMTimer& timer)
{
    m_DOMTimerList.add(timer);
}
```

Later on when the timer's callback is [finished executing](https://github.com/WebKit/WebKit/blob/e7780d735de3975ec8bf854e4ed70d07c7648497/Source/WebCore/page/ios/ContentChangeObserver.cpp#L348-L357):

```cpp
void ContentChangeObserver::domTimerExecuteDidFinish(const DOMTimer& timer)
{
    if (!m_observedDomTimerIsBeingExecuted)
        return;
    LOG_WITH_STREAM(ContentObservation, stream << "stopObservingDOMTimerExecute: stop observing (" << &timer << ") timer callback.");

    m_observedDomTimerIsBeingExecuted = false;
    unregisterDOMTimer(timer);
    adjustObservedState(Event::EndedDOMTimerExecution);
}
```

The state change [leads to](https://github.com/WebKit/WebKit/blob/e7780d735de3975ec8bf854e4ed70d07c7648497/Source/WebCore/page/ios/ContentChangeObserver.cpp#L538-L691):

```cpp
void ContentChangeObserver::adjustObservedState(Event event)
{
    // These events (DOM timer, transition and style recalc) could trigger style changes that are candidates to visibility checking.
    {
        // ...
        if (event == Event::EndedDOMTimerExecution) {
            if (m_document.hasPendingStyleRecalc()) {
                setShouldObserveNextStyleRecalc(true);
                return;
            }
            notifyClientIfNeeded();
            return;
        }
        // ...
    }
}
```

which reports whether or not a content change was observed to the page code, information that can be used to determine whether or not to fire a `click` event.

There's one last place we need to inspect to complete this puzzle: [`WebPage::handleSyntheticClick`](https://github.com/WebKit/WebKit/blob/e7780d735de3975ec8bf854e4ed70d07c7648497/Source/WebKit/WebProcess/WebPage/ios/WebPageIOS.mm#L758-L832).

```cpp
void WebPage::handleSyntheticClick(Node& nodeRespondingToClick, const WebCore::FloatPoint& location, OptionSet<WebEventModifier> modifiers, WebCore::PointerID pointerId)
{
    auto& respondingDocument = nodeRespondingToClick.document();
    auto isFirstSyntheticClickOnPage = !m_hasHandledSyntheticClick;
    m_hasHandledSyntheticClick = true;

    if (!respondingDocument.settings().contentChangeObserverEnabled() || respondingDocument.quirks().shouldDisableContentChangeObserver() || respondingDocument.quirks().shouldIgnoreContentObservationForSyntheticClick(isFirstSyntheticClickOnPage)) {
        completeSyntheticClick(nodeRespondingToClick, location, modifiers, WebCore::SyntheticClickType::OneFingerTap, pointerId);
        return;
    }

    auto& contentChangeObserver = respondingDocument.contentChangeObserver();
    auto targetNodeWentFromHiddenToVisible = contentChangeObserver.hiddenTouchTarget() == &nodeRespondingToClick && ContentChangeObserver::isConsideredVisible(nodeRespondingToClick);
    {
        LOG_WITH_STREAM(ContentObservation, stream << "handleSyntheticClick: node(" << &nodeRespondingToClick << ") " << location);
        ContentChangeObserver::MouseMovedScope observingScope(respondingDocument);
        auto* localMainFrame = dynamicDowncast<LocalFrame>(m_page->mainFrame());
        if (!localMainFrame)
            return;
        auto& mainFrame = *localMainFrame;
        dispatchSyntheticMouseMove(mainFrame, location, modifiers, pointerId);
        mainFrame.document()->updateStyleIfNeeded();
        if (m_isClosed)
            return;
    }

    if (targetNodeWentFromHiddenToVisible) {
        LOG(ContentObservation, "handleSyntheticClick: target node was hidden and now is visible -> hover.");
        send(Messages::WebPageProxy::DidHandleTapAsHover());
        return;
    }

    auto nodeTriggersFastPath = [&](auto& targetNode) {
        if (!is<Element>(targetNode))
            return false;
        if (is<HTMLFormControlElement>(targetNode))
            return true;
        if (targetNode.document().quirks().shouldIgnoreAriaForFastPathContentObservationCheck())
            return false;
        auto ariaRole = AccessibilityObject::ariaRoleToWebCoreRole(downcast<Element>(targetNode).getAttribute(HTMLNames::roleAttr));
        return AccessibilityObject::isARIAControl(ariaRole);
    };
    auto targetNodeTriggersFastPath = nodeTriggersFastPath(nodeRespondingToClick);

    auto observedContentChange = contentChangeObserver.observedContentChange();
    auto continueContentObservation = !(observedContentChange == WKContentVisibilityChange || targetNodeTriggersFastPath);
    if (continueContentObservation) {
        // Wait for callback to completePendingSyntheticClickForContentChangeObserver() to decide whether to send the click event.
        const Seconds observationDuration = 32_ms;
        contentChangeObserver.startContentObservationForDuration(observationDuration);
        LOG(ContentObservation, "handleSyntheticClick: Can't decide it yet -> wait.");
        m_pendingSyntheticClickNode = &nodeRespondingToClick;
        m_pendingSyntheticClickLocation = location;
        m_pendingSyntheticClickModifiers = modifiers;
        m_pendingSyntheticClickPointerId = pointerId;
        return;
    }
    contentChangeObserver.stopContentObservation();
    callOnMainRunLoop([protectedThis = Ref { *this }, targetNode = Ref<Node>(nodeRespondingToClick), location, modifiers, observedContentChange, pointerId] {
        if (protectedThis->m_isClosed || !protectedThis->corePage())
            return;

        auto shouldStayAtHoverState = observedContentChange == WKContentVisibilityChange;
        if (shouldStayAtHoverState) {
            // The move event caused new contents to appear. Don't send synthetic click event, but just ensure that the mouse is on the most recent content.
            if (auto* localMainFrame = dynamicDowncast<WebCore::LocalFrame>(protectedThis->corePage()->mainFrame()))
                dispatchSyntheticMouseMove(*localMainFrame, location, modifiers, pointerId);
            LOG(ContentObservation, "handleSyntheticClick: Observed meaningful visible change -> hover.");
            protectedThis->send(Messages::WebPageProxy::DidHandleTapAsHover());
            return;
        }
        LOG(ContentObservation, "handleSyntheticClick: calling completeSyntheticClick -> click.");
        protectedThis->completeSyntheticClick(targetNode, location, modifiers, WebCore::SyntheticClickType::OneFingerTap, pointerId);
    });
}
```

At the beginning of the function we see some conditions that can cause the `click` event to be fired immediately without any further delay:

```cpp
auto& respondingDocument = nodeRespondingToClick.document();
auto isFirstSyntheticClickOnPage = !m_hasHandledSyntheticClick;
m_hasHandledSyntheticClick = true;

if (!respondingDocument.settings().contentChangeObserverEnabled() || respondingDocument.quirks().shouldDisableContentChangeObserver() || respondingDocument.quirks().shouldIgnoreContentObservationForSyntheticClick(isFirstSyntheticClickOnPage)) {
    completeSyntheticClick(nodeRespondingToClick, location, modifiers, WebCore::SyntheticClickType::OneFingerTap, pointerId);
    return;
}
```

Nothing too interesting here; it's mainly handling quirks to support specific sites that need hardcoded assistance. If we look a bit further down though:

```cpp
auto nodeTriggersFastPath = [&](auto& targetNode) {
    if (!is<Element>(targetNode))
        return false;
    if (is<HTMLFormControlElement>(targetNode))
        return true;
    if (targetNode.document().quirks().shouldIgnoreAriaForFastPathContentObservationCheck())
        return false;
    auto ariaRole = AccessibilityObject::ariaRoleToWebCoreRole(downcast<Element>(targetNode).getAttribute(HTMLNames::roleAttr));
    return AccessibilityObject::isARIAControl(ariaRole);
};
auto targetNodeTriggersFastPath = nodeTriggersFastPath(nodeRespondingToClick);
```

This is handy stuff, and ultimately what I was able to use to get out of the debacle I started with. `role="button"` and various other ARIA roles (full list contained in the `isARIAControl` method) can be used to easily opt out of this content observation behavior, eliminating the delay involved in waiting on the `setTimeout` callback to finish executing.

We then see where the code avoids firing the `click` event, instead awaiting the results of content observation:

```cpp
auto observedContentChange = contentChangeObserver.observedContentChange();
auto continueContentObservation = !(observedContentChange == WKContentVisibilityChange || targetNodeTriggersFastPath);
if (continueContentObservation) {
    // Wait for callback to completePendingSyntheticClickForContentChangeObserver() to decide whether to send the click event.
    const Seconds observationDuration = 32_ms;
    contentChangeObserver.startContentObservationForDuration(observationDuration);
    LOG(ContentObservation, "handleSyntheticClick: Can't decide it yet -> wait.");
    m_pendingSyntheticClickNode = &nodeRespondingToClick;
    m_pendingSyntheticClickLocation = location;
    m_pendingSyntheticClickModifiers = modifiers;
    m_pendingSyntheticClickPointerId = pointerId;
    return;
}
```

and that's that. Mystery solved! If `setTimeout` is delaying your `click` event from firing on mobile iOS, now we know why.

I spent hours of my time going down this rabbit hole, and if a blog post like this had existed in a discoverable place it could have saved me a lot of time. Shoutout to my good friend [Nick McGuire](https://mastodon.social/@nickmcguire) for rubber ducking with me while I was working on this.

As a side note, there's a lot of logging in WebKit around content observation and the various events that lead to the `setTimeout` call blocking the `click` event from firing. It would be cool to see all of that logging integrated in some way with the web inspector console; if I had been able to see everything all together I could have figured out what was happening much, much faster.

And before you say it, yes, I know semantically nothing here means `setTimeout` is blocking the event loop. It's blocking other things. Sue me for clickbait :).
