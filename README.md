# Tag Verify
A darktable plugin for imposing tag constraints.

## About

Do you use Darktable to organise your photo collection? Do you have a detailed system for tagging photos, and need to make sure that every photo is appropriately tagged? Then this is the module for you!

`Tag Verify` consists of a language for expressing constraints on tag systems, and a Darktable module that lets you write tag constraints and detect whether your photo collection satisfies them.

## Examples (and explanation)

#### Example 1: Locations 

Darktable uses a hierarchal tag system, that allows for tags to have 'subtags', denoted by the bar `|`.

As an example, consider the set of tags:

```
places|France|Nord|Lille
places|France|Nord
places|France
places|England
```

A photo taken in Lille (photo 1) would have the tags

```
places|France|Nord|Lille
places|France|Nord
places|France
```

Whereas one taken in Nord (photo 2) but not in Lille might be tagged

```
places|France|Nord
places|France
```

And a photo taken in England (photo 3) could have just the tag

```
places|England
```

In order to express conditions like "every photo should have precisely one tag that begins with `places`", we'll need to distinguish between terminal and non-terminal tag. Given a set of tags `ts`, we'll call a given tag `t` *terminal* if `t` is not a proper prefix of any other tag in `ts`. 

The terminal tags of the above photos are therefore

1. `places|France|Nord|Lille`
2. `places|France|Nord`
3. `places|England`

Note that being terminal is a property of a tag in a set, and `places|France|Nord` is terminal in photo 2 but not in photo 1. We see that each photo indeed has one *terminal* tag that matches `places|%`. So, the Tag Verify set expressions are only concerned with terminal tags: evaluating `"places|%"` at photo 1 would return the singleton set $\{ \text{places|France|Nord|Lille} \}$.

To specify that each image must be tagged with a single location, you could use the rule `eq(num("places|%"),1)`.



#### Example 2: Formats 

If you take photos digitally, and on 35mm and 120 film, you might have the tags
```
Digital
Film|35mm
Film|120
```

To express the constraint that every photo must have precisely one of those tags, you could use the rule `"Digital" xor "Film|%"`. Here, we use the fact that when a set is used in the position of a rule, it is interpreted as `leq(1, set)` (i.e. iff it is inhabited)/

Further, if you organise your photos by actual film rolls, you might want to say that in every roll, every photo should have the same format tag. This is what the `roll` function allows: `roll(union("Digital", "Film|%"))` (meditate on why use of the union operator is necessary...)


## Syntax and Semantics

```
<Rule> = <Primitive> | <Rule> or <Rule> | <Rule> and <Rule> | <Rule> xor <Rule> | if(<Rule>, <Rule>) | not <Rule>
<Primitive> = eq(<Int>, <Int>) | eq(<Set>, <Set>) | leq(<Int>, <Int>) | subset(<Set>, <Set>) | roll(<Set>) | true | false
<Set> = "<Exact Tag>" | "<Partial Tag>" | { <Tag>, <Tag>> ... <Tag> } | union(<Set>, <Set>) | intersect(<Set>, <Set>)
<Int> = n | num(<Set>)
```

Tag Verify uses a modal logic for expressing constraints on image tags. An informal bnf specification of the language is given above (informal because extra whitespace is usually permitted!). A rule can be evaluated at any specific image, and may evaluate to either true or false.

The logical connectives and comparison functions behave in the usual way. The denotation of a set expression at an image `x` is the set of terminal tags of `x` that match the expression. There are three ways of defining sets of tags.

1. An exact tag "t" , which is interpreted as the set $\{s \in \text{terminal\_tags}(x) : s = t \}$
2. A partial tag "t|%", which is interpreted as the set $\{s \in \text{terminal\_tags}(x) : t \text{ is a prefix of } s \}$
3. A finite set of (exact) tags, expressed as `{ tag, tag, tag }`. Note that no tag should be the prefix of another--- `{a, |\b}` will be interpreted as the set `{a|b}`.


For example, consider an image `x` with tags `a, a|b, a|b|c, a|d`.

|set expression |type| denotation at x |
|---------------|----|------------|
|"a" | exact tag| a|
|"a|b" | exact tag| a|b|
|"a|%" | partial tag | a|b, a|b|c, a|d
|"d" | exact tag| $\emptyset$ |
|"a|b|%" | partial tag |  |
|{ "e", "f"} |primitive set | e, f|


While darktable will allow a tag name to contain any character except the bar, we will need to make some further restrictions. A valid `tag name` may consist of any characters except for the separator `|`, wildcard `%`, braces `{,}`, comma `,`, and double quotes `"` (notably, spaces are allowed).

An `exact tag` is a list of tag names, separated by the bar `|`. A `partial tag` also a list of tag names separated by the bar, but the final name must be the wildcard.

The `roll` is a pseudo-modal operator that allows for enforcing tag set equality across an entire film roll. The semantics of `roll(set)` at an image x is that for every image y in the same film roll as x, the tag sets `set(x)` and `set(y)` must be equal.

For example, if you wish to express the condition that every image in a film roll must have been taken by the *same camera*, the rule `eq("Camera|%",1)` is not sufficient. But the rule `roll("Camera|%")` would encode this condition.


## Usage
The plugin provides a UI interface for adding new rules. Rules may be typed into the 'new rule' entry box, and added with 'add' button. An error will pop up if the rule does not parse. The active rules appear listed in the box below. Hovering over an image will indicate whether every the active rules are valid or not. The 'edit' and 'delete' buttons allow for editing and deleting rules, and the 'clear' button will remove every added rule.

Also, a 'select badly tagged' button is added to the selection module. Clicking this button will select all the images that fail at least one rule. 


## Install:

1. Compile the lpeg module. The source may be found [here](http://www.inf.puc-rio.br/~roberto/lpeg/). Move the produced `lpeg.so` file into `tag_verify`.

2. Optionally run tests with `lua test.lua` (requires the [lust](https://github.com/bjornbytes/lust) module)

3. Identify your darktable config directory: [config]. This may be either `$HOME/.config/darktable`, or (if you have installed darktable via flatpack) `$HOME/.var/app/org.darktable.Darktable/config/darktable`.


4. Move the `tag_verify` directory (or at least the three files `tag_verify.lua`, and `parse.lua`, and `lpeg.so`) to `[config]/lua/tag_verify`.

5. Add the following lines to your `[config]/luarc` file

```
package.cpath = "[config]/lua/tag_verify/lpeg.so;" .. package.cpath
require "tag_verify/tag_verify"
```

