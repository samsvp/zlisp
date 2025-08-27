(defmacro defn
  (fn [&args]
    (let [fn-name (first args)
          body (rest args)]
      ('def fn-name (cons 'fn body)))))

(defn enumerate [col]
  "Returns a tuple containing the index and value of each item in the collection.
   e.g '(= (enumerate [5 9 10]) [(0 5) (1 9) (2 10)])'"
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

;; for x in [1 2 3] (* 2 x)
(defmacro for
  (fn [value in col ast]
    (if (= in :in)
      ('map ('fn [value] ast) col)
      (throw "'for' macro missing ':in' keyword"))))
