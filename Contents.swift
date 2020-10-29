import Foundation

// Standard Composition for pure functions
func compose<A, B, C>(
    _ f: @escaping (A) -> B,
    _ g: @escaping (B) -> C
) -> (A) -> C {
    return { g(f($0)) } // "f after g" or "g∘f"
}

// SideEffect or Kleisli Composition, Fish >=>
// defined using flatMap (AKA bind in Monads) >>=
// Kleisli arrow is (A) -> SomeContainer<B>
// Fish composes two Kleislli arrows
// bind or flatMap accepts a Kleisli arrow
func fish<A, B, C>(
    _ f: @escaping (A) -> B?,
    _ g: @escaping (B) -> C?
) -> (A) -> C? {
    return { a in
        f(a).flatMap(g)
    }
    //    return { a in
    //        guard let b = f(a) else { return nil }
    //        return g(b)
    //    }
}

func fish<A, B, C>(
    _ f: @escaping (A) -> [B],
    _ g: @escaping (B) -> [C]
) -> ((A) -> [C]) {
    return { a in
        f(a).flatMap(g)
    }
}

func fish<A, B, C>(
    _ f: @escaping (A) -> (B, [String]),
    _ g: @escaping (B) -> (C, [String])
) -> (A) -> (C, [String]) {
    
    return { a in
        let (b, logs) = f(a)
        let (c, moreLogs) = g(b)
        return (c, logs + moreLogs)
    }
}

// Where "F" is any container
// contra map:    ((C)    ->   A ) -> ((F<A>)       -> F<C>)
// map:           ((A)    ->   C ) -> ((F<A>)       -> F<C>)
// zip(with:):    ((A, B) ->   C ) -> ((F<A>, F<B>) -> F<C>)
// flatMap:       ((A)    -> F<C>) -> ((F<A>)       -> F<C>)
// kleisli arrow: ((A)    -> F<C>)

// map touches items inside containers, Functor
// zip helps flip containers and join data
// flatMap helps sequencing and handle failable transformations, Monad

/*
 A Functor is a structure that preserves mappings between objects and arrows. It preserves identity and composition. If we can define a "true map" on a container type then it is a Functor. A true map preserves identity and "the map of a composition is the composition of the maps" where map(f >>> g) == map(f) >>> m(g).
 With this definition a Set is not a Functor becasue it does not have a true map. A Set in Swift requires its elements to conform to Hashable which destroys genericity by constraining types. It is also destructive and thus the order of composition matters meaning it doesn't preserve composition or map(f >>> g) != map(f) >>> m(g). Similarily, a Dictionary's Keys do not have a map but they are also in the contravarient position.
 */

extension Array {
    func map<B>(_ f: (Element) -> B) -> [B]{
        var result = [B]()
        for item in self {
            result.append(f(item))
        }
        return result
    }
    
    func flatMap<B>(_ f: (Element) -> [B]) -> [B] {
        var result: [B] = []
        for element in self {
            result.append(contentsOf: f(element))
        }
        return result
    }
    
    func newMap<B>(_ f: (Element) -> B) -> [B] {
        return self.flatMap { [f($0)] }
    }
}

func zip2<A, B>(_ xs: [A], _ ys: [B]) -> [(A, B)] {
    var result: [(A, B)] = []
    (0..<min(xs.count, ys.count)).forEach { idx in
        result.append((xs[idx], ys[idx]))
    }
    return result
}

func zip2<A, B, C>(
    with f: @escaping (A, B) -> C
) -> ([A], [B]) -> [C] {
    return { zip2($0, $1).map(f) }
}

func zip3<A, B, C>(_ xs: [A], _ ys: [B], _ zs: [C]) -> [(A, B, C)] {
    return zip2(xs, zip2(ys, zs)) // [(A, (B, C))]
        .map { a, bc in (a, bc.0, bc.1) } // map to flatten tuples
}

// can't make zip out of flapMap for Array becasue it behaves like a combo func

extension Optional {
    func map<B>(_ f: (Wrapped) -> B) -> B?{
        switch self {
        case let .some(value):
            return .some(f(value))
        case .none:
            return .none
        }
    }
    
    func flatMap<B>(_ f: (Wrapped) -> B?) -> B? {
        switch self {
        case let .some(value):
            return f(value)
        case .none:
            return .none
        }
    }
    
    func newMap<B>(_ f: (Wrapped) -> B) -> B? {
        return self.flatMap { Optional<B>.some(f($0)) }
    }
}

func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a = a, let b = b else { return nil }
    return (a, b)
}

func zip2<A, B, C>(
    with f: @escaping (A, B) -> C
) -> (A?, B?) -> C? {
    return { zip2($0, $1).map(f) }
}

func zip3<A, B, C>(_ a: A?, _ b: B?, _ c: C?) -> (A, B, C)? {
    return zip2(a, zip2(b, c))
        .map { a, bc in (a, bc.0, bc.1) }
}

func newZip<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    return a.flatMap { a in
        b.flatMap { b in
            Optional.some((a, b))
        }
    }
}

struct PredicateSet<A> {
    let contains: (A) -> Bool
    
    // contravarient to map left side A to B isn't possible with map
    func contramap<B>(_ f: @escaping (B) -> A) -> PredicateSet<B> {
        return PredicateSet<B> { b in
            self.contains(f(b))
        }
    }
    
    // we can rename contramap to pullback following category theory and math
    // pullback name is better to us from Local to Global or Subclass to Superclass
    func pullback<B>(_ f: @escaping (B) -> A) -> PredicateSet<B> {
        return self.contramap(f)
    }
}

enum Result<A, E> {
    case success(A)
    case failure(E)
    
    func map<B>(_ f: (A) -> B) -> Result<B, E> {
        switch self {
        case let .success(value):
            return .success(f(value))
        case let .failure(e):
            return .failure(e)
        }
    }
    
    func flatMap<B>(_ f: (A) -> Result<B, E>) -> Result<B, E> {
        switch self {
        case let .success(value):
            return f(value)
        case let .failure(error):
            return .failure(error)
        }
    }
    
    func newMap<B>(_ f: (A) -> B) -> Result<B, E> {
        return self.flatMap { .success(f($0)) }
    }
    
    // Result is a Bifunctor because we can map both parameters
    func bimap<B,F>(_ f: (A) -> B, _ g: (E) -> F) -> Result<B, F>{
        switch self {
        case let .success(value):
            return .success(f(value))
        case let .failure(e):
            return .failure(g(e))
        }
    }
}

func zip2<A, B, E>(_ a: Result<A, E>, _ b: Result<B, E>) -> Result<(A, B), E> {
    switch (a, b) {
    case let (.success(a), .success(b)):
        return .success((a, b))
    case let (.success, .failure(e)):
        return .failure(e)
    case let (.failure(e), .success):
        return .failure(e)
    case let (.failure(e1), .failure(e2)):
        return .failure(e1) // loses context of .failure(e2) unlike Validated
    }
}

func zip2<A, B, C, E>(
    with f: @escaping (A, B) -> C
) -> (Validated<A, E>, Validated<B, E>) -> Validated<C, E> {
    
    return { zip2($0, $1).map(f) }
}

func newZip<A, B, E>(_ a: Result<A, E>, _ b: Result<B, E>) -> Result<(A, B), E> {
    return a.flatMap { a in
        b.flatMap { b in
            Result.success((a, b))
        }
    }
}

struct F1<A> {
    let value: A
    
    func map<B>(_ f: @escaping (A) -> B) -> F1<B> {
        return F1<B>(value: f(self.value))
    }
}

enum Validated<A, E> {
    case valid(A)
    case invalid(NonEmptyArray<E>)
    
    func map<B>(_ f: (A) -> B) -> Validated<B, E> {
        switch self {
        case let .valid(a):
            return .valid(f(a))
        case let .invalid(e):
            return .invalid(e)
        }
    }
    
    func flatMap<B>(_ f: (A) -> Validated<B, E>) -> Validated<B, E> {
        switch self {
        case let .valid(value):
            return f(value)
        case let .invalid(error):
            return .invalid(error)
        }
    }
    
    func newMap<B>(_ f: (A) -> B) -> Validated<B, E> {
        return self.flatMap { .valid(f($0)) }
    }
}

func zip2<A, B, E>(_ a: Validated<A, E>, _ b: Validated<B, E>) -> Validated<(A, B), E> {
    
    switch (a, b) {
    case let (.valid(a), .valid(b)):
        return .valid((a, b))
    case let (.valid, .invalid(e)):
        return .invalid(e)
    case let (.invalid(e), .valid):
        return .invalid(e)
    case let (.invalid(e1), .invalid(e2)):
        return .invalid(e1 + e2)
    }
}

// can't make a zip out of flapMap for Validated becasue it will not concat more than one error

struct Func<A, C> {
    let apply: (A) -> C
    
    // maps right side C to D
    func map<D>(_ f: @escaping(C) -> D) -> Func<A, D> {
        return Func<A, D> { a in
            f(self.apply(a))
        }
    }
    
    // maps left side A to B
    func contramap<B>(_ f: @escaping(B) -> A) -> Func<B, C> {
        return Func<B, C> { b in
            self.apply(f(b))
        }
    }
    
    func flatMap<D>(_ f: @escaping (C) -> Func<A, D>) -> Func<A, D> {
        return Func<A, D> { a -> D in
            f(self.apply(a)).apply(a)
        }
    }
    
    func newMap<D>(_ f: @escaping (C) -> D) -> Func<A, D> {
        return self.flatMap { c in Func<A, D> { _ in f(c) } }
    }
}

func zip2<A, C, D>(_ a2c: Func<A, C>, _ a2d: Func<A, D>) -> Func<A, (C, D)> {
    return Func<A, (C, D)> { a in
        (a2c.apply(a), a2d.apply(a))
    }
}

func zip2<A, C, D, E>(
    with f: @escaping (C, D) -> E
) -> (Func<A, C>, Func<A, D>) -> Func<A, E> {
    return { zip2($0, $1).map(f) }
}

func newZip<A, C, D>(_ a: Func<A, C>, _ b: Func<A, D>) -> Func<A, (C, D)> {
    return a.flatMap { c in
        b.flatMap { d in
            Func { _ in (c, d) }
        }
    }
}

struct Parallel<A> {
    let run: (@escaping (A) -> Void) -> Void
    
    // A is covariant even though no left side ( consider -1 + -1 = +1)
    func map<B>(_ f: @escaping (A) -> B) -> Parallel<B> {
        return Parallel<B>{ callback in
            self.run { a in
                callback(f(a))
            }
        }
    }
    
    func flatMap<B>(_ f: @escaping (A) -> Parallel<B>) -> Parallel<B> {
        return Parallel<B> { callback in
            self.run { a in
                f(a).run(callback)
            }
        }
    }
    
    // rename for flatMap
    func then<B>(_ f: @escaping (A) -> Parallel<B>) -> Parallel<B> {
        return self.flatMap(f)
    }
    
    func newMap<B>(_ f: @escaping (A) -> B) -> Parallel<B> {
        return self.flatMap { a in Parallel<B> { callback in callback(f(a)) } }
    }
}

func zip2<A, B>(_ fa: Parallel<A>, _ fb: Parallel<B>) -> Parallel<(A, B)> {
    return Parallel<(A, B)> { callback in
        let group = DispatchGroup()
        
        var a: A?
        var b: B?
        
        group.enter()
        fa.run { a = $0; group.leave() }
        
        group.enter()
        fb.run { b = $0; group.leave() }
        
        group.notify(queue: .main) {
            guard let a = a, let b = b else { return }
            callback((a, b))
        }
    }
}

func zip2<A, B, C>(
    with f: @escaping (A, B) -> C
) -> (Parallel<A>, Parallel<B>) -> Parallel<C> {
    return { zip2($0, $1).map(f) }
}

// can't make zip out of flapMap for Parallel becasue it each run will be blocking


// F<A> = Array<A>
// F<A> = Optional<A>
// F<A> = Result<A, E>
// F<A> = Validated<A, E>
// F<A> = Func<A0, A>
// F<A> = Parallel<A>


// map:        ((A)    ->  C ) -> (([A])      -> [C])
// zip(with:): ((A, B) ->  C ) -> (([A], [B]) -> [C])
// flatMap:    ((A)    -> [C]) -> (([A])      -> [C])

// map:        ((A)    -> C ) -> ((A?)     -> C?)
// zip(with:): ((A, B) -> C ) -> ((A?, B?) -> C?)
// flatMap:    ((A)    -> C?) -> ((A?)     -> C?)

// map:        ((A)    ->        C    ) -> ((Result<A, E>)               -> Result<C, E>)
// zip(with:): ((A, B) ->        C    ) -> ((Result<A, E>, Result<B, E>) -> Result<C, E>)
// flatMap:    ((A)    -> Result<C, E>) -> ((Result<A, E>)               -> Result<C, E>)

// map:        ((A)    ->           C    ) -> ((Validated<A, E>)                  -> Validated<C, E>)
// zip(with:): ((A, B) ->           C    ) -> ((Validated<A, E>, Validated<B, E>) -> Validated<C, E>)
// flatMap:    ((A)    -> Validated<C, E>) -> ((Validated<A, E>)                  -> Validated<C, E>)

// map:        ((B)    ->         D ) -> ((Func<A, B>)             -> Func<A, D>)
// zip(with:): ((B, C) ->         D ) -> ((Func<A, B>, Func<A, C>) -> Func<A, D>)
// flatMap:    ((B)    -> Func<A, D>) -> ((Func<A, B>)             -> Func<A, D>)

// map:        ((A)    ->          C ) -> ((Parallel<A>)              -> Parallel<C>)
// zip(with:): ((A, B) ->          C ) -> ((Parallel<A>, Parallel<B>) -> Parallel<C>)
// flatMap:    ((A)    -> Parallel<C>) -> ((Parallel<A>)              -> Parallel<C>)
