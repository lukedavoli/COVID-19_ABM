globals [
  hours ;; hours since the beginning of the simulation
  infected-y ;; turtles infected at the end of the prior day
  region-boundaries-x ;; a list of regions definitions, where each region is a list of its min pxcor and max pxcor
  region-boundaries-y
  infected-today
  economic-contributors
  economy
]

turtles-own [
  infected?    ;; has the person been infected with the disease?
  worker?
  home-patch
  workplace
  hours-worked-today
  hours-shopped-today
  infectious?
  infected-hours
  incubation-hours
  asymptomatic-hours
  recovery-hours
  chance-travel-sick
  mask?
]

patches-own [
  region-x
  region-y
  region-type
]

;;;;;;;;;;;;;;;;;;;;;;;;
;;; Setup Procedures ;;;
;;;;;;;;;;;;;;;;;;;;;;;;

to setup
  clear-all
  setup-regions number-of-regions-squared
  set-default-shape turtles "person"
  make-turtles
  infect
  recolor
  set hours 0
  set economic-contributors 0
  set infected-y (count turtles with [ infected? ])
  reset-ticks
end

to setup-regions [ num-regions ]
  foreach region-divisions-x num-regions draw-region-division-x
  foreach region-divisions-y num-regions draw-region-division-y

  set region-boundaries-x calculate-region-boundaries-x num-regions
  set region-boundaries-y calculate-region-boundaries-y num-regions

  let region-numbers-x (range 1 (num-regions + 1))
  (foreach region-boundaries-x region-numbers-x [ [boundaries region-number] ->
    ask patches with [ pxcor >= first boundaries and pxcor <= last boundaries ] [
      set region-x region-number
    ]
  ])
  let region-numbers-y (range 1 (num-regions + 1))
  (foreach region-boundaries-y region-numbers-y [ [boundaries region-number] ->
    ask patches with [ pycor >= first boundaries and pycor <= last boundaries ] [
      set region-y region-number
    ]
  ])
  ask patches with [region-y > (num-regions / 4) and pcolor != 6.5][
   set pcolor 34
   set region-type "home"
  ]
  ask patches with [region-y <= (num-regions / 4) and region-x > (num-regions / 4) and pcolor != 6.5][
   set pcolor 104
   set region-type "workplace"
  ]
  ask patches with [region-y <= (num-regions / 4) and region-x <= (num-regions / 4) and pcolor != 6.5][
   set pcolor 114
   set region-type "shop"
  ]
end

to-report calculate-region-boundaries-x [ num-regions ]
  let divisions-x region-divisions-x num-regions
  report (map [ [d1 d2] -> list (d1 + 1) (d2 - 1) ] (but-last divisions-x) (but-first divisions-x))
end

to-report calculate-region-boundaries-y [ num-regions ]
  let divisions-y region-divisions-y num-regions
  report (map [ [d1 d2] -> list (d1 + 1) (d2 - 1) ] (but-last divisions-y) (but-first divisions-y))
end

to-report region-divisions-x [ num-regions ]
  report n-values (num-regions + 1) [ n ->
    [ pxcor ] of patch (min-pxcor + (n * ((max-pxcor - min-pxcor) / num-regions))) 0
  ]
end

to-report region-divisions-y [ num-regions ]
  report n-values (num-regions + 1) [ n ->
    [ pycor ] of patch 0 (min-pycor + (n * ((max-pycor - min-pycor) / num-regions)))
  ]
end

to draw-region-division-x [ x ]
  ask patches with [ pxcor = x ] [
    set pcolor grey + 1.5
  ]
  create-turtles 1 [
    setxy x max-pycor + 0.5
    set heading 0
    set color grey - 3
    pen-down
    forward world-height
    set xcor xcor + 1 / patch-size
    right 180
    set color grey + 3
    forward world-height
    die
  ]
end

to draw-region-division-y [ y ]
  ask patches with [ pycor = y ] [
    set pcolor grey + 1.5
  ]
  create-turtles 1 [
    setxy max-pxcor + 0.5 y
    set heading 90
    set color grey - 3
    pen-down
    forward world-width
    set ycor ycor + 1 / patch-size
    right 90
    set color grey + 3
    forward world-width
    die
  ]
end

to make-turtles
  create-turtles num-people [
    set infected? false
    set infectious? false
    setxy random-xcor random-ycor
    set home-patch one-of patches with [region-type = "home"]
    set hours-worked-today 0
    set hours-shopped-today 0
    set chance-travel-sick 101
    move-to home-patch
    ifelse random 100 < employment-rate[
      set worker? true
      set workplace one-of patches with [region-type = "workplace"]
    ][
      set worker? false
    ]
    ifelse random 100 < percentage-masks[set mask? true][set mask? false]
    set incubation-hours round random-normal 144 60
    if incubation-hours < 1 [set incubation-hours 168]
    set asymptomatic-hours (random 24 + 48)
    set recovery-hours round (300 + abs random-normal 0 300)
  ]
end

to infect
  ask n-of num-infected turtles [
    set infected? true
    set infected-hours 0
  ]
end

to recolor
  ask turtles [
    ;; infected turtles are red, others are gray
    set color ifelse-value infected? [ red ] [ gray ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;
;;; Main Procedures ;;;
;;;;;;;;;;;;;;;;;;;;;;;

to go
  if all? turtles [ infected? ] [ stop ]
  if count turtles with [infected?] = 0 [ stop ]
  spread-infection
  ask turtles [
    travel
    update-infection-status
  ]
  move
  set hours hours + 1
  if (hours mod 24) = 0 [
    update-r0-plot
    update-economy
    set infected-y count turtles with [ infected? ]
    set infected-today 0
  ]
  tick
end

to update-infection-status
  if infected? = true[
    if infected-hours = 0 [set infected-today infected-today + 1]
    set infected-hours infected-hours + 1

    if infected-hours < incubation-hours - asymptomatic-hours [
      set color yellow
    ]
    if infected-hours < incubation-hours and infected-hours > incubation-hours - asymptomatic-hours[
      set color orange
      set infectious? true
    ]
    if infected-hours > incubation-hours[
      set color red
      if infected-hours = incubation-hours + 1[set chance-travel-sick random 100]
    ]
    if infected-hours > recovery-hours[
      set color green
      set infected? false
      set infectious? false
      set infected-hours 0
      set chance-travel-sick 101
    ]
  ]
end

to travel
  if mask? = True[
    if chance-travel-sick > travel-sick-threshold[
      if (hours mod 24) >= 7 and (hours mod 24) < 12 and worker? = true[
        ;; Intention for workers to have a roughly 70% chance of going to work on any given day,
        ;; so they are given a 14% chance on 5 opportunities between 7am and 11am to head to work
        if random 100 < 14[
          move-to workplace
          set economic-contributors economic-contributors + 1
        ]
      ]

      if (hours mod 24) >= 7 and (hours mod 24) < 17 and worker? = false[
        ;; Intention for non-workers to have a roughly 40% chance of going to the shops on any given day,
        ;; so they are given a 3% chance on 10 opportunities between 7am and 5pm to head to the shops
        if random 100 < 4[
          move-to one-of patches with [pcolor = 114]
          set economic-contributors economic-contributors + 1
        ]
      ]
    ]

    if pcolor = 104[set hours-worked-today hours-worked-today + 1]
    if pcolor = 114[set hours-shopped-today hours-shopped-today + 1]

    if pcolor = 104 and hours-worked-today = 6[
      ;; Intention for workers have a roughly 20% chance of going to the shops after work
      ifelse random 100 < 20[
        move-to one-of patches with [pcolor = 114]
      ][
        move-to home-patch
      ]
      set hours-worked-today 0

    ]

    if pcolor = 114 and hours-shopped-today = 3[
      move-to home-patch
      set hours-shopped-today 0
    ]
  ]


end

to spread-infection
  ask turtles with [ infected? ][
    if infectious? = true[
      ifelse mask? = true[ ;; carrier is wearing a mask...
        ask turtles-here [
          if mask? = true and random 100 < 20[ ;; ...and contact is too
            set infected? true
          ]
          if mask? = false and random 100 < 50[ ;; ...but contact is not
            set infected? true
          ]
        ]
      ][
        ask turtles-here [ ;; carrier is not wearing a mask...
          if mask? = true and random 100 < 80[ ;; ...but contact is
            set infected? true
          ]
          if mask? = false[ ;; ...and neither is contact
            set infected? true
          ]
        ]
      ]
    ]
  ]
end

;;;;;;;;;;;;;;
;;; Layout ;;;
;;;;;;;;;;;;;;
to move
  ask turtles [
    bounce
    fd 1
  ]
end

to bounce
  ; check: hitting left or right wall?
  if [region-x] of patch-ahead 1.5 = 0
    ; if so, reflect heading around x axis
    [ set heading (- heading) ]
  ; check: hitting top or bottom wall?
  if [region-y] of patch-ahead 1.5 = 0
    ; if so, reflect heading around y axis
    [ set heading (180 - heading) ]
end

to update-r0-plot
  set-current-plot "R0 vs. Day"
  set-current-plot-pen "r0"
  plot (((infected-y + infected-today) / infected-y) - 1)
end

to update-economy
  set economy round ((economic-contributors / num-people) * 100)
  set economic-contributors 0
end

;; This procedure allows you to run the model multiple times
;; and measure how long it takes for the disease to spread to
;; all people in each run. For more complex experiments, you
;; would use the BehaviorSpace tool instead.
to my-experiment
  repeat 10 [
    set num-people 50
    setup
    while [ not all? turtles [ infected? ] ] [ go ]
    print ticks
  ]
end


; Copyright 2008 Uri Wilensky.
; See Info tab for full copyright and license.
@#$#@#$#@
GRAPHICS-WINDOW
395
10
1018
634
-1
-1
7.6
1
10
1
1
1
0
1
1
1
-40
40
-40
40
1
1
1
ticks
30.0

BUTTON
10
150
65
185
setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
70
150
125
185
go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

SLIDER
200
10
385
43
num-people
num-people
2
500
280.0
1
1
NIL
HORIZONTAL

BUTTON
130
150
185
185
go once
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

SLIDER
10
10
185
43
num-infected
num-infected
1
num-people
1.0
1
1
NIL
HORIZONTAL

PLOT
10
190
295
345
Infection vs. Time
Time
NIL
0.0
10.0
0.0
1.0
true
true
"" ""
PENS
"people" 1.0 0 -5298144 true "" "plot count turtles with [ infected? ] / count turtles"

MONITOR
305
190
385
235
Infected
count turtles with [ infected? ]
3
1
11

MONITOR
305
245
385
290
NIL
hours
17
1
11

PLOT
10
355
385
475
R0 vs. Day
day
R0
0.0
7.0
0.0
1.0
true
true
"" ""
PENS
"r0" 1.0 0 -5825686 true "" ""

SLIDER
10
55
185
88
number-of-regions-squared
number-of-regions-squared
4
20
12.0
4
1
NIL
HORIZONTAL

SLIDER
200
55
385
88
employment-rate
employment-rate
1
100
80.0
1
1
NIL
HORIZONTAL

PLOT
10
485
385
635
State of Disease
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"healthy" 1.0 0 -7500403 true "" "plot count turtles with [color = gray]"
"incubation" 1.0 0 -1184463 true "" "plot count turtles with [color = yellow]"
"asymptomatic" 1.0 0 -955883 true "" "plot count turtles with [color = orange]"
"infectious" 1.0 0 -2674135 true "" "plot count turtles with [color = red]"
"recovered" 1.0 0 -13840069 true "" "plot count turtles with [color = green]"

SLIDER
10
105
185
138
travel-sick-threshold
travel-sick-threshold
1
100
50.0
1
1
NIL
HORIZONTAL

MONITOR
305
300
385
345
NIL
economy
17
1
11

SLIDER
200
105
385
138
percentage-masks
percentage-masks
30
100
90.0
1
1
NIL
HORIZONTAL

@#$#@#$#@
## ACKNOWLEDGMENT

This model is from Chapter Six of the book "Introduction to Agent-Based Modeling: Modeling Natural, Social and Engineered Complex Systems with NetLogo", by Uri Wilensky & William Rand.

* Wilensky, U. & Rand, W. (2015). Introduction to Agent-Based Modeling: Modeling Natural, Social and Engineered Complex Systems with NetLogo. Cambridge, MA. MIT Press.

This model is in the IABM Textbook folder of the NetLogo Models Library. The model, as well as any updates to the model, can also be found on the textbook website: http://www.intro-to-abm.com/.

## WHAT IS IT?

This model explores the spread of disease in a number of different conditions and environments. In particular, it explores how making assumptions about the interactions of agents can drastically affect the results of the model.

## HOW IT WORKS

The SETUP procedure creates a population of agents. Depending on the value of the VARIANT chooser, these agents have different properties. In the NETWORK variant they are linked to each other through a social network. In the MOBILE and ENVIRONMENTAL variants they move around the landscape. At the start of the simulation, NUM-INFECTED of the agents are infected with a disease.

The GO procedure spreads the disease among the agents. In the case of the NETWORK variant this is along the social network links. In the case of the MOBILE or ENVIRONMENTAL variant, the disease is spread to nearby neighbors in the physical space. In the case of the ENVIRONMENTAL variant the disease is also spread via the environment. Finally, if the variant is either the MOBILE or ENVIRONMENTAL variant then the agents move.

## HOW TO USE IT

The NUM-PEOPLE slider controls the number of people in the world.

The VARIANT chooser controls how the infection spreads.

NUM-INFECTED controls how many individuals are initially infected with the disease.

The CONNECTIONS-PER-NODE slider controls how many connections to other nodes each node tries to make in the NETWORK variant.

The DISEASE-DECAY slider controls how quickly the disease leaves the current environment.

To use the model, set these parameters and then press SETUP.

Pressing the GO ONCE button spreads the disease for one tick. You can press the GO button to make the simulation run until all agents are infected.

The REDO LAYOUT button runs the layout-step procedure continuously to improve the layout of the network.

## THINGS TO NOTICE

How do the different variants affect the spread of the disease?

In particular, look at how the different parameters of the model influence the speed at which the disease spreads through the population. For example, in the "mobile" variant, the population (NUM-PEOPLE) clearly seem to be the main driving force for the speed of infection. Is that the case for the other two variants as well? Some suggestions of parameters to vary are given below under THINGS TO TRY.

Another thing that you may have noticed is that, in the "network" variant, there are cases where the disease will not spread to all people. This happens when the network has more than one [components](https://en.wikipedia.org/wiki/Connected_component_%28graph_theory%29) (isolated nodes, or groups of nodes that are not connected with the rest of the network) and that not all components get infected with the disease right from the start. NetLogo's [network extension](http://ccl.northwestern.edu/netlogo/docs/nw.html) has [a primitive](http://ccl.northwestern.edu/netlogo/docs/nw.html#weak-component-clusters) that can help you identify the components of a network.

## THINGS TO TRY

Set different values for the DISEASE-DECAY slider and run the ENVIRONMENTAL variant. How does the DISEASE-DECAY slider affect the results?

Similarly, set different values for the CONNECTIONS-PER-NODE slider and run the NETWORK variant. How does the CONNECTIONS-PER-NODE slider affect the results?

If you open the BehaviorSpace tool, you will see that we have a defined a few experiments that can be used to explore the behavior of the model more systematically. Try these out, and look at the data in the resulting CSV file. Are those results similar to what you obtained by manually playing with the model parameters? Can you confirm that using your favorite external analysis tool?

## EXTENDING THE MODEL

Can you think of additional variants and parameters that could affect the spread of a disease?

At the moment, in the environmental variant of the model, patches are either infected or not. DISEASE-DECAY allows you to set how long they stay infected, but they are fully contagious until they suddenly stop being infected. Do you think it would be more realistic to have their infection level decline gradually? The probability of a person catching the disease from a patch could become smaller as the infection level decreases on the patch. If you want to make the model look really nice, you could vary the color of the patch using the [`scale-color`](http://ccl.northwestern.edu/netlogo/docs/dictionary.html#scale-color) primitive.

## RELATED MODELS

NetLogo is very good at simulating the spread of epidemics, so there are a few disease transmission model in the library:

- HIV
- Disease Solo
- Disease HubNet
- Disease Doctors HubNet
- epiDEM Basic
- epiDEM Travel and Control
- Virus on a Network

Some communication models are also very similar to disease transmission ones:

- Communication T-T Example
- Communication-T-T Network Example
- Language Change

## NETLOGO FEATURES

One particularity of this model is that it combines three different "variants" in the same model. The way this is accomplished in the code of the model is fairly simple: we have a few `if`-statements making the model behave slightly different, depending on the value of the VARIANT chooser.

A more interesting element is the **Infection vs. Time** plot. In the "mobile" and "network" variants, the plot is the same: we simply plot the number of infected persons. In the "environmental" variant, however, we want to plot an additional quantity: the number of infected patches. To achieve that, we use the "Plot update commands" field of our plot definition. Just like the "Pen update commands", these commands run every time a plot is updated (usually when calling [`tick`](http://ccl.northwestern.edu/netlogo/docs/dictionary.html#tick)). In this case, we use the [`create-temporary-plot-pen`](http://ccl.northwestern.edu/netlogo/docs/dictionary.html#create-temporary-plot-pen) primitive to make sure that we have a pen for the number of infected patches, and actually plot that number:

```
if variant = "environmental" [
  create-temporary-plot-pen "patches"
  plotxy ticks count patches with [ p-infected? ] / count patches
]
```

One nice thing about this NetLogo feature is that the temporary plot pen that we create is automatically added to the plot's legend (and removed from the legend when the plot is cleared, when calling [`clear-all`](http://ccl.northwestern.edu/netlogo/docs/dictionary.html#clear-all)).

## HOW TO CITE

This model is part of the textbook, ???Introduction to Agent-Based Modeling: Modeling Natural, Social and Engineered Complex Systems with NetLogo.???

If you mention this model or the NetLogo software in a publication, we ask that you include the citations below.

For the model itself:

* Rand, W., Wilensky, U. (2008).  NetLogo Spread of Disease model.  http://ccl.northwestern.edu/netlogo/models/SpreadofDisease.  Center for Connected Learning and Computer-Based Modeling, Northwestern Institute on Complex Systems, Northwestern University, Evanston, IL.

Please cite the NetLogo software as:

* Wilensky, U. (1999). NetLogo. http://ccl.northwestern.edu/netlogo/. Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.

Please cite the textbook as:

* Wilensky, U. & Rand, W. (2015). Introduction to Agent-Based Modeling: Modeling Natural, Social and Engineered Complex Systems with NetLogo. Cambridge, MA. MIT Press.

## COPYRIGHT AND LICENSE

Copyright 2008 Uri Wilensky.

![CC BY-NC-SA 3.0](http://ccl.northwestern.edu/images/creativecommons/byncsa.png)

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 3.0 License.  To view a copy of this license, visit https://creativecommons.org/licenses/by-nc-sa/3.0/ or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

Commercial licenses are also available. To inquire about commercial licenses, please contact Uri Wilensky at uri@northwestern.edu.

<!-- 2008 Cite: Rand, W., Wilensky, U. -->
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

link
true
0
Line -7500403 true 150 0 150 300

link direction
true
0
Line -7500403 true 150 150 30 225
Line -7500403 true 150 150 270 225

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.1.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="population-density" repetitions="10" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>ticks</metric>
    <enumeratedValueSet variable="variant">
      <value value="&quot;mobile&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="connections-per-node">
      <value value="4.1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="num-people" first="50" step="50" last="200"/>
    <enumeratedValueSet variable="num-infected">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="disease-decay">
      <value value="0"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="degree" repetitions="10" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>count turtles with [infected?]</metric>
    <enumeratedValueSet variable="num-people">
      <value value="200"/>
    </enumeratedValueSet>
    <steppedValueSet variable="connections-per-node" first="0.5" step="0.5" last="4"/>
    <enumeratedValueSet variable="disease-decay">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="variant">
      <value value="&quot;network&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-infected">
      <value value="1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="environmental" repetitions="10" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>ticks</metric>
    <enumeratedValueSet variable="num-people">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="connections-per-node">
      <value value="4"/>
    </enumeratedValueSet>
    <steppedValueSet variable="disease-decay" first="0" step="1" last="10"/>
    <enumeratedValueSet variable="variant">
      <value value="&quot;environmental&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-infected">
      <value value="1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="density-and-decay" repetitions="10" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>ticks</metric>
    <enumeratedValueSet variable="variant">
      <value value="&quot;environmental&quot;"/>
    </enumeratedValueSet>
    <steppedValueSet variable="disease-decay" first="0" step="1" last="10"/>
    <enumeratedValueSet variable="num-infected">
      <value value="1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="num-people" first="50" step="50" last="200"/>
    <enumeratedValueSet variable="connections-per-node">
      <value value="4"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
1
@#$#@#$#@
