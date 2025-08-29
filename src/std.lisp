(defmacro defn
  (fn
    "Defines a new function with the given name.
     Examples:
       (defn square [x] (* x x))
       (let [closure-arg 2] (defn add-2 [closure-arg] [a] (+ closure-arg a)))
       (let [five 5] (defn mult-5 \"docstring\" [five] [x] (* x five)))"
    [&args]
    (let [fn-name (first args)
          body (rest args)]
      ('def fn-name (cons 'fn body)))))

(defn enumerate
  "Returns a tuple containing the index and value of each item in the collection.
   Examples:
   (= (enumerate [5 9 10]) [(0 5) (1 9) (2 10)])"
  [col]
  (let [i (atom -1)]
    (map
      (fn [i] [v]
        (let [_ (swap! i (fn [a b] (+ a b)) 1)]
          ((deref i) v)))
      col)))

(defn infix [infixed]
  ((nth infixed 1) (nth infixed 0) (nth infixed 2)))

(defmacro cond
  (fn [&xs]
    (if (> (count xs) 0)
      ('if (head xs)
        (if (> (count xs) 1)
          (nth xs 1)
          (throw "odd number of forms to cond"))
        (cons 'cond (tail (tail xs)))))))

(defmacro for
  (fn
    "Python like list comprehension.
     Examples
       (= (for x :in [1 2 3] (* 2 x)) [2 4 6])
       (defn square [x] (* x x))
       (= (for x :in (1 2 3) (square x)) (1 4 9))"
    [value in col ast]
    (if (= in :in)
      ('map ('fn [value] ast) col)
      (throw "'for' macro missing ':in' keyword"))))
