# Testing

The project's test rungs, from the cheapest to the most expensive. `trellis sync` writes the table from the `[rung]` sections of `trellis.config`; a "no" in the "Claude runs it" column becomes a `deny` in `.claude/settings.json`.

<!-- trellis:rungs -->
<!-- /trellis:rungs -->

## Base rules

- Never against production.
- A test touches no network that does not belong to it: external services are replaced at the edge.
- No quarantine for flaky tests: a flaky test is fixed, or deleted with the code it covers.
- Coverage is honest: a test that cannot fail does not count.
- Every new test is seen failing before it is seen passing.
- The tests of a rung that no pull request runs at least compile or are analyzed in the pull request's rung, and the pull request body says which rung is left waiting.

## Rungs

{{One section per rung, with the same name as its `[rung]`:}}

### {{rung name}}

- What it proves: {{...}}
- What it does not prove: {{...}}
- When a new test goes here: {{...}}

## Where does a new test go?

{{A short decision map, such as: pure logic without dependencies, the unit rung; a widget with its state, the widget rung; a flow across screens with services replaced, the integration rung.}}
